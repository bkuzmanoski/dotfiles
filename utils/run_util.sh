#!/bin/zsh

local script_name="${RUN_UTIL_COMMAND_NAME:-${0:t}}"

function print_usage() {
  cat <<-EOF
		Usage:
		  ${script_name} [options] <command_or_source_file> [command_args...]

		Options:
		  -b, --background    Run the command in the background (no output to terminal)
		  -B, --build-only    Only compile the command if needed, do not execute it
		  -h, --help          Show this help message
	EOF
}

function die() {
  print -u2 -- "Error: $1"
  exit ${2:-1}
}

# shellcheck disable=SC2034
if ! zparseopts -D -F \
  {b,-background}=flag_background \
  {B,-build-only}=flag_build_only \
  {h,-help}=flag_help \
  2>/dev/null; then
  print -u2 -- "Error: Invalid option(s).\n"
  print_usage >&2
  exit 1
fi

if (($#flag_help)); then
  print_usage
  exit 0
fi

if (($# < 1)); then
  print -u2 -- "Error: No command specified.\n"
  print_usage >&2
  exit 1
fi

local util_name="${1:t:r}"
shift

local sources_dir="${0:A:h}/sources"
local bin_dir="${0:A:h}/bin"
local -a candidate_source_files=("${sources_dir}/${util_name}".*(N.))

if ((${#candidate_source_files[@]} == 0)); then
  die "Missing source file for utility."
elif ((${#candidate_source_files[@]} > 1)); then
  print -u2 "Warning: Multiple source files found for '${util_name}'. Using \"${candidate_source_files[1]:t}\"."
fi

local source_file="${candidate_source_files[1]}"
local source_file_extension="${source_file##*.}"
local bin_path="${bin_dir}/${util_name}"

if [[ "${source_file_extension}" == "applescript" ]]; then
  bin_path="${bin_path}.scpt"
fi

function compile_util() {
  rm -rf "${bin_path}"
  mkdir -p "${bin_dir}"

  case "${source_file_extension}" in
  swift)
    if ! swiftc -O -o "${bin_path}" "${source_file}"; then
      die "Swift compilation failed."
    fi
    ;;

  applescript)
    if ! osacompile -o "${bin_path}" "${source_file}"; then
      die "AppleScript compilation failed."
    fi
    ;;

  *)
    die "Unsupported source file type: .${source_file_extension}"
    ;;
  esac
}

function run_and_exit() {
  if (($#flag_background)); then
    nohup "$@" >/dev/null 2>&1 &
    exit 0
  else
    exec "$@"
  fi
}

if [[ ! -e "${bin_path}" || "${source_file}" -nt "${bin_path}" ]]; then
  compile_util
fi

if (($#flag_build_only)); then
  exit 0
fi

if [[ "${source_file_extension}" == "swift" && -x "${bin_path}" ]]; then
  run_and_exit "${bin_path}" "$@"

elif [[ "${source_file_extension}" == "applescript" && -e "${bin_path}" ]]; then
  run_and_exit osascript "${bin_path}" "$@"

else
  die "Failed to locate executable."
fi
