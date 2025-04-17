# Combine files
cf() {
  if ! command -v rg >/dev/null 2>&1; then
    print -P "%Brg%b is not installed. Install with: brew install ripgrep"
    return 1
  fi

  local glob_pattern output_file
  while [[ "$1" == -* ]]; do
    case "$1" in
      "-g"|"--glob")
        if [[ -n "$2" ]]; then
          glob_pattern="$2"
          shift 2
        else
          print "Please specify a glob pattern or omit the option."
          return 1
        fi
        ;;
      "-o"|"--output")
        if [[ -n "$2" ]]; then
          output_file="$2"
          shift 2
        else
          print "Please specify an output file or omit the option."
          return 1
        fi
        ;;
      "-h"|"--help")
        print "Usage: cf [options]"
        print "Options:"
        print "  -g, --glob      Specify a glob pattern to search for files (default: all text files)"
        print "  -o, --output    Specify an output file to write the output to (default: copy to clipboard)"
        print "  -h, --help      Show this help message"
        return 0
        ;;
      *)
        print "Unknown option: $1"
        return 1
        ;;
    esac
  done

  local rg_cmd=("rg" "--heading" "--line-number" "--color=never")
  [[ -n "${glob_pattern}" ]] && rg_cmd+=("--glob" "${glob_pattern}")
  rg_cmd+=(".")

  local rg_output rg_status return_message
  if [[ -n "${output_file}" ]]; then
    "${rg_cmd[@]}" >| "${output_file}"
    rg_status=$?
    return_message="Output written to file: ${output_file}"
  else
    rg_output=$("${rg_cmd[@]}")
    rg_status=$?
    [[ ${rg_status} -eq 0 && -n "${rg_output}" ]] && { print -n "${rg_output}" | pbcopy }
    return_message="Output copied to clipboard."
  fi

  local return_code=0
  if [[ ${rg_status} -eq 0 ]]; then
    print "${return_message}"
  elif [[ ${rg_status} -eq 1 ]]; then
    print "No matches found."
  else
    return_code=1
  fi

  [[ ${return_code} -ne 0 && -n "${output_file}" && -f "${output_file}" ]] && rm "${output_file}"
  return ${return_code}
}
