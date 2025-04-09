#!/bin/zsh

if (( $# != 1 )); then
  print "Usage: ${0:t} <command_or_source_file>"
  exit 1
fi

local input="$1"
local helpers_dir="${0:A:h}"
local command="${input:t:r}"
local command_path="${helpers_dir}/bin/${command}"

[[ -x "${command_path}" ]] && {
  "${command_path}"
  exit $?
}

local source_files=(${helpers_dir}/${command}.*)
if [[ "${#source_files[@]}" -eq 0 || ! -e "${source_files[1]}" ]]; then
  print "Unknown command: ${command}"
  exit 1
fi

local source_file="${source_files[1]}"
local extension="${source_file##*.}"

mkdir -p "${helpers_dir}/bin"

case "${extension}" in
  "swift")
    swiftc -O "${source_file}" -o "${command_path}" || {
      print "Compilation failed"
      exit 1
    }

    "${command_path}"
    exit $?
    ;;
  *)
    print "Unsupported command type: ${extension}"
    exit 1
    ;;
esac
