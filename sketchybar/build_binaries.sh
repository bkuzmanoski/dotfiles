#!/bin/zsh

SOURCE_DIR="${0:A:h}/helpers"
BIN_DIR="${SOURCE_DIR}/bin"

mkdir -p "${BIN_DIR}"

local source_files=("${SOURCE_DIR}"/*.swift(N))
for source_file in "${source_files[@]}"; do
  target_path="${BIN_DIR}/$(basename "${source_file}" .swift)"
  if [ ! -x "${target_path}" ]; then
    swiftc -O "${source_file}" -o "${target_path}"
  fi
done
