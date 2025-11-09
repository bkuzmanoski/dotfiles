#!/bin/zsh

zparseopts -D -E {b,-background}=flag_background

if (( $# < 1 )); then
  print -u2 "Usage: ${0:t} [-b, --background] <command_or_source_file> [command_args...]"
  exit 1
fi

local command_name="$1"
shift

local utils_dir="${0:A:h}"
local bin_dir="${utils_dir}/bin"
local command="${command_name:t:r}"
local compiled_path="${bin_dir}/${command}"
local applescript_path="${compiled_path}.scpt"

compile_command() {
  local source_files=(${utils_dir}/${command}.*)

  if [[ "${#source_files[@]}" -eq 0 || ! -e "${source_files[1]}" ]]; then
    print -u2 "Error: Unknown command"
    return 1
  fi

  local source_file="${source_files[1]}"
  local extension="${source_file##*.}"

  mkdir -p "${bin_dir}"

  case "${extension}" in
    "swift")
      if ! swiftc -O -o "${compiled_path}" "${source_file}"; then
        print -u2 "Error: Swift compilation failed for ${source_file:t}"
        return 1
      fi
      ;;
    "applescript")
      if ! osacompile -o "${applescript_path}" "${source_file}"; then
        print -u2 "Error: AppleScript compilation failed for ${source_file:t}"
        return 1
      fi
      ;;
    *)
      print -u2 "Error: Unsupported command source type: .${extension}"
      return 1
      ;;
  esac

  return 0
}

run_and_exit() {
  if (( ${#flag_background} > 0 )); then
    nohup "$@" >/dev/null 2>&1 &
    exit 0
  else
    "$@"
    exit $?
  fi
}

if [[ -x "${compiled_path}" ]]; then
  run_and_exit "${compiled_path}" "$@"
elif [[ -e "${applescript_path}" ]]; then
  run_and_exit osascript "${applescript_path}" "$@"
else
  if compile_command; then
    exec "${0:A}" ${flag_background:+"--background"} "${command_name}" "${@}"
  else
    exit 1
  fi
fi
