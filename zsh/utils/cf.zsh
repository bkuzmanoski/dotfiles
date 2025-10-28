cf() {
  if ! command -v rg >/dev/null 2>&1; then
    print -u2 -P "%Brg%b is not installed. Install with: brew install ripgrep"
    return 1
  fi

  _help() {
    print "Usage: cf [options] [rg options]"
    print "Options:"
    print "  -o, --output    Specify an output file to write the output to (default: copy to clipboard)"
    print "  -h, --help      Show this help message"
  }

  if ! zparseopts -D -E -K {o,-output}:=output_file {h,-help}=flag_help 2>/dev/null; then
    print -u2 "Error: Invalid options provided.\n"
    _help

    return 1
  fi

  [[ -z "${flag_help}" ]] || { _help; return 0 }

  local return_message return_code
  local -a rg_cmd=("rg" "--heading" "--line-number" "--color=never" "${@}" ".")
  local rg_output

  rg_output=$("${rg_cmd[@]}")

  local rg_status=$?

  case "${rg_status}" in
    0)
      if [[ -n "${output_file[-1]}" ]]; then
        print -r -- "${rg_output}" >| "${output_file[-1]}"
        return_message="Output written to file: ${output_file[-1]}"
      else
        print -rn -- "${rg_output}" | pbcopy
        return_message="Output copied to clipboard."
      fi

      return_code=0
      ;;
    1)
      return_message="No matches found."
      return_code=0
      ;;
    *)
      return_message="\nripgrep failed with exit code: ${rg_status}"
      return_code=1
      ;;
  esac

  case "${return_code}" in
    0)
      print "${return_message}"
      ;;
    *)
      print -u2 "${return_message}"
      ;;
  esac

  return ${return_code}
}
