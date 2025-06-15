# Generate shell command using LLM
ai() {
  if [[ $# -eq 0 ]]; then
    print "Usage: ai <prompt>"
    return 1
  fi

  local api_key_file="${HOME}/.config/zsh/ai_api_key"
  local instructions="You will be given a prompt to generate a shell command for Zsh on macOS. You should output only the executable command without any additional text, explanations, or formatting. If multiple commands are needed, separate them with && or ;. If the prompt is unclear or potentially dangerous, output \"LLM_ERROR: <brief reason>\" instead.

    Available custom functions:
    - cv [options] <video>: Compress video using ffmpeg (options: -p <preset>, -q <quality>, -f <fps>, -c <codec>, -a <audio>, --overwrite)
    - oi [options] <image|directory>...: Optimize PNG/JPEG images using oxipng/jpegoptim (options: --zopfli, -q <quality>)
    - cf [options]: Combine files in current directory using ripgrep, copy to clipboard (options: -g <glob>, -o <output_file>)
    - fdir [command]: Select directories with fzf+fd, optionally pass to command
    - ff [command]: Select files with fzf+fd, optionally pass to command
    - fif <pattern> [command]: Select files containing pattern with fzf+ripgrep, optionally pass to command
    - fh: Select from command history with fzf
    - fk [signal]: Kill processes interactively with fzf

    Available aliases:
    - ls → eza --all --group-directories-first --oneline
    - lt → eza --all --group-directories-first --tree --level 3
    - ll → eza --all --group-directories-first --header --long --no-permissions --no-user
    - llt → eza --all --group-directories-first --header --long --no-permissions --no-user --tree --level 3
    - mkdir → mkdir -pv
    - mv → mv -i
    - cp → cp -iv
    - rm → rm -i
    - fd → fd --hidden --no-ignore-vcs --color never
    - cat → bat
    - top → top -s 1 -S -stats pid,command,cpu,th,mem,purg,user,state

    Available third-party tools: bat, eza, fd, ffmpeg, fnm, fzf, jpegoptim, micro, nextdns, oxipng, ripgrep. For everything else, use only built-in macOS/Xcode CLT commands (e.g. networkquality -s instead of speedtest)."

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
    print "Error: Failed to contact API"
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

  if [[ -z "${output}" ]]; then
    output="PARSE_ERROR"
  fi

  case "${output}" in
    "API_ERROR: "*)
      print "Error: ${output#API_ERROR: }"
      return 1
      ;;
    "PARSE_ERROR")
      print "Error: Invalid API response"
      return 1
      ;;
    "LLM_ERROR: "*)
      print "Error: ${output#LLM_ERROR: }"
      return 1
      ;;
    *)
      print -rz "${output}"
      ;;
  esac
}
