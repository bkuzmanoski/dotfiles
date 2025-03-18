# Calulations using Wolfram|Alpha
wa() {
  if [[ $# -eq 0 ]]; then
    print "Usage: wa <expression>"
    return 1
  fi

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
  return 0
}
