#!/bin/zsh

SCRIPT_DIR="${0:A:h}"

if (( $# != 1 )); then
  print "Usage: $0 <command_or_source_file>"
  exit 1
fi

local input="$1"
local base="${input:t}"        # Extract basename
local command="${base%%.*}"
local command_path="${SCRIPT_DIR}/bin/${command}"

if [[ -x "${command_path}" ]]; then
  "${command_path}"
  exit $?
fi

local source_files=(${SCRIPT_DIR}/${command}.*)
if [[ ${#source_files[@]} -eq 0 || ! -e ${source_files[1]} ]]; then
  echo "Unknown command: ${command}"
  exit 1
fi

local source_file=${source_files[1]}
local extension="${source_file##*.}"

mkdir -p "${SCRIPT_DIR}/bin"

case ${extension} in
  "swift")
    if ! swiftc -O -o "${command_path}" "${source_file}"; then
      print "Compilation failed"
      exit 1
    fi

    "${command_path}"
    exit $?
    ;;
  *)
    print "Unsupported command type: ${extension}"
    exit 1
    ;;
esac
