# Calulations using Wolfram|Alpha
wa() {
  if [[ -z ${WA_APPID} ]]; then
    print "Error: \$WA_APPID is not set. Get one at https://developer.wolframalpha.com/access"
    return 1
  fi

  local wa_response wa_status
  wa_response=$(curl --silent "https://api.wolframalpha.com/v1/result?appid=${WA_APPID}&units=metric&" --data-urlencode "i=$*")
  wa_status=$?
  if [[ ${wa_status} -ne 0 ]]; then
    print "Error: Failed to connect to Wolfram|Alpha (curl status: ${wa_status})."
    return 1
  fi

  print "${wa_response}"

  [[ "${wa_response}" == "No short answer available" || "${wa_response}" == "Wolfram|Alpha did not understand your input" ]] && return 1
  return 0
}
