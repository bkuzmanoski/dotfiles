ai() {
  if [[ $# -eq 0 ]]; then
    print -u2 "Usage: ai <prompt>"
    return 1
  fi

  local api_key_file="${HOME}/.config/zsh/ai_api_key"
  local instructions="You will be given a prompt to generate a shell command for Zsh on macOS. You should output only an executable command without any additional text, explanations, or formatting. If multiple commands are needed, separate them with && or ;. If you are unable to generate a command, output \"LLM_ERROR: <brief reason>\" instead. Available third-party tools: bat, eza, fd, ffmpeg, fnm, fzf, jpegoptim, micro, oxipng, ripgrep. For everything else, use only built-in macOS or Xcode CLT commands."

  local api_key
  local prompt="$*"

  [[ ! -d "$(dirname "${api_key_file}")" ]] && mkdir -p "$(dirname "${api_key_file}")" >/dev/null

  if [[ -f "${api_key_file}" ]]; then
    api_key=$(< "${api_key_file}")
  else
    print "Enter your OpenRouter API key: "
    read -rs api_key
    print "${api_key}" > "${api_key_file}"
    chmod 600 "${api_key_file}"
  fi

  local response=$(curl -s https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n \
      --arg instructions "${instructions}" \
      --arg prompt "${prompt}" \
      '{
        "model": "anthropic/claude-sonnet-4",
        "messages": [
          {
            "role": "system",
            "content": $instructions
          },
          {
            "role": "user",
            "content": $prompt
          }
        ]
      }')")

  if [[ -z "${response}" ]]; then
    print -u2 "Error: Failed to contact API"
    return 1
  fi

  local output=$(print "${response}" | jq -r '
    if .choices[0].message.content then
      .choices[0].message.content
    elif .error.message then
      "API_ERROR: " + .error.message
    else
      "PARSE_ERROR"
    end
  ' 2>/dev/null)

  if [[ -z "${output}" || "${output}" == "PARSE_ERROR" ]]; then
    output=$(print "${response}" | sed -n 's/.*"content":"\(.*\)","refusal".*/\1/p')
    [[ -z "${output}" ]] && output="PARSE_ERROR"
  fi

  case "${output}" in
    "API_ERROR: "*)
      print -u2 "Error: ${output#API_ERROR: }"
      return 1
      ;;
    "PARSE_ERROR")
      print -u2 "Error: Could not parse API response\n"
      print -u2 "Raw response:"
      print -u2 "${response}"
      return 1
      ;;
    "LLM_ERROR: "*)
      print -u2 "Error: ${output#LLM_ERROR: }"
      return 1
      ;;
    *)
      print -rz "${output}"
      ;;
  esac
}
