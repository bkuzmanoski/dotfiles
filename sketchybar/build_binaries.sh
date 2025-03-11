#!/bin/zsh

SCRIPT_DIR="${0:A:h}"

typeset -A scripts
scripts=(
  ["SBEventProvider"]="${SCRIPT_DIR}/events/SBEventProvider.swift"
  ["GetNextEvent"]="${SCRIPT_DIR}/helpers/GetNextEvent.swift"
  ["GetAppIcon"]="${SCRIPT_DIR}/helpers/GetAppIcon.swift"
)

for binary in ${(k)scripts}; do
  source_file="${scripts[${binary}]}"
  source_dir="$(dirname "${source_file}")"
  output_dir="${source_dir}/bin"
  mkdir -p "${output_dir}"
  output_file="${output_dir}/${binary}"
  if [ ! -f "${output_file}" ]; then
    swiftc -O "${source_file}" -o "${output_file}" || { print "Failed to build ${binary}"; exit 1; }
  fi
done
