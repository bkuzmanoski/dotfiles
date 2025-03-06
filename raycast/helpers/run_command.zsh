run_command() {
  local source_dir="${SCRIPT_DIR}/helpers"
  local source_file="${1:t}"
  shift

  local command="${source_file%%.*}"
  local command_path="${source_dir}/bin/${command}"

  if [[ ! -x "${command_path}" ]]; then
    local source_files=(${source_dir}/${command}.*)
    if [[ ${#source_files[@]} -eq 0 || ! -e ${source_files[1]} ]]; then
      print "Command not found: ${command}"
      return 1
    fi

    local source_file=${source_files[1]}
    local extension="${source_file##*.}"

    mkdir -p "${source_dir}/bin"

    case ${extension} in
      "swift")
        if ! swiftc -O "${source_file}" -o "${command_path}"; then
          print "Command compilation failed"
          return 1
        fi
        ;;
      *)
        print "Unsupported command type: ${extension}"
        return 1
        ;;
    esac
  fi

  output=$("${command_path}" "${@}" 2>&1)

  if [[ ${?} -eq 0 ]]; then
    print "${output}"
  else
    print "Error: ${output}"
    return 1
  fi
}
