# Calulations using Wolfram|Alpha
wa() {
  if [[ -z ${WA_APPID} ]]; then
    print "Error: \$WA_APPID is not set. Get one at https://developer.wolframalpha.com/access"
    return 1
  fi

  local silent=0
  if [[ "$1" == (-s|--silent) ]]; then
    silent=1
    shift
  fi

  local wa_response wa_status
  wa_response=$(curl --silent "https://api.wolframalpha.com/v1/result?appid=${WA_APPID}&units=metric&" --data-urlencode "i=$*")
  wa_status=$?
  if [[ ${wa_status} -ne 0 ]]; then
    [[ ${silent} -eq 0 ]] && print "Error: Failed to connect to Wolfram|Alpha (curl status: ${wa_status})."
    return 1
  fi

  case "${wa_response}" in
    "No short answer available"|"Wolfram|Alpha did not understand your input")
      [[ ${silent} -eq 0 ]] && print "${wa_response}"
      return 1
      ;;
    *)
      print "${wa_response}"
      return 0
      ;;
  esac
}
