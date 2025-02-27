#!/bin/zsh

SCRIPT_DIR="${0:A:h}"

typeset -A scripts
scripts=(
  ["AppChange"]="${SCRIPT_DIR}/events/AppChange.swift"
  ["GetNextEvent"]="${SCRIPT_DIR}/helpers/GetNextEvent.swift"
  ["GetAppIcon"]="${SCRIPT_DIR}/helpers/GetAppIcon.swift"
)

for binary in ${(k)scripts}; do
  src="${scripts[${binary}]}"
  src_dir=$(dirname "${src}")
  output_dir="${src_dir}/bin"
  mkdir -p "${output_dir}"
  output_file="${output_dir}/${binary}"
  if [ ! -f "${output_file}" ]; then
    swiftc -O -o "${output_file}" "$src" || { print "Failed to build ${binary}"; exit 1; }
  fi
done
