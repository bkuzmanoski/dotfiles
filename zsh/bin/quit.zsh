quit() {
  local pid=$$
  local comm=""

  while [[ "${pid}" -gt 1 ]]; do
    read -r pid comm <<< "$(ps -o ppid=,comm= -p "${pid}")"

    if [[ "${comm}" == *".app"* ]]; then
      osascript -e "quit app \"$(basename "${comm%.app*}")\""
      return 0
    fi
  done

  print -u2 "Terminal app not found."
  return 1
}
