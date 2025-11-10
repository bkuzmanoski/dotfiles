ai() {
  if [[ $# -eq 0 ]]; then
    print -u2 "Usage: ai <prompt>"
    return 1
  fi

  local instructions=$(cat <<- EOF
		Generate a shell command for Zsh on macOS based on the provided prompt.
		Output the command without additional text, explanations, or formatting.
		Ensure the command is safe to run and does not require additional context.
		If multiple commands are needed, separate them with \`&&\` or \`;\`.
		The following tools are available: Xcode Command Line Tools, bat, eza, fd, ffmpeg, fnm, fzf, gh, jpegoptim, micro, oxipng, ripgrep, watch.
		If the prompt is unclear or cannot be fulfilled, respond with: "LLM_ERROR: <brief reason>".
		EOF
  )
  local api_key_file="${HOME}/.config/zsh/ai_api_key"
  local api_key
  local prompt="$*"

  if [[ ! -d "$(dirname "${api_key_file}")" ]]; then
    mkdir -p "$(dirname "${api_key_file}")" >/dev/null
  fi

  if [[ -f "${api_key_file}" ]]; then
    api_key="$(< "${api_key_file}")"
  else
    print "Enter your OpenRouter API key: "
    read -rs api_key
    print "${api_key}" > "${api_key_file}"
    chmod 600 "${api_key_file}"
  fi

  local response="$(curl -s https://openrouter.ai/api/v1/chat/completions \
    -H "Authorization: Bearer ${api_key}" \
    -H "Content-Type: application/json" \
    -d "$(jq \
      --null-input \
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
      }'
    )"
  )"

  if [[ -z "${response}" ]]; then
    print -u2 "\nError: Failed to contact API"
    return 1
  fi

  local output="$(print "${response}" | jq --raw-output '
    if .choices[0].message.content then
      .choices[0].message.content
    elif .error.message then
      "API_ERROR: " + .error.message
    else
      "PARSE_ERROR"
    end
  ' 2>/dev/null)"

  if [[ -z "${output}" || "${output}" == "PARSE_ERROR" ]]; then
    output="$(print "${response}" | sed -n 's/.*"content":"\(.*\)","refusal".*/\1/p')"

    if [[ -z "${output}" ]]; then
      output="PARSE_ERROR"
    fi
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
