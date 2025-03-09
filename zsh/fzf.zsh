FZF_OPTS=(
  --height=100%
  --layout=reverse
  --prompt=""
  --info=inline:""
  --no-separator
  --pointer=""
  --marker="✓"
  --marker-multi-line="✓  "
  --highlight-line
  --ellipsis="…"
  --bind "enter:accept+abort"
)

fzf() {
  update_theme && command fzf "${FZF_OPTS[@]}" --color "${FZF_THEME}" "${@}"
}

select_paths() {
  local find_command="${1}"
  shift

  local selected_paths=("${(@f)$(${(@s: :)find_command} | fzf --scheme path --multi)}")

  [[ -z ${selected_paths[@]} ]] && return

  if [[ ${#} -gt 0 ]]; then
    print -rz -- "${@} ${(@q)selected_paths}"
  else
    print -r -- "${(@q)selected_paths}" | pbcopy
    print "Copied to clipboard."
  fi
}

fdir() {
  select_paths "fd --type d --hidden" "${@}"
}

ff() {
  select_paths "fd --type f --hidden" "${@}"
}

fif() {
  if [ -z "${1}" ]; then
    echo "Usage: fif <search_pattern>"
    return 1
  fi

  local pattern="${1}"
  shift

  select_paths "rg --files-with-matches \"${pattern}\"" "${@}"
}

fh() {
  local selected_command=$(fc -nl 1 | tail -r | fzf --scheme history)
  print -rz -- "${selected_command}"
}

fk() {
  local selected_processes=$(ps -eo pid,comm | sed -E "1d; s/^([[:space:]]*)([0-9]+)/\2\1/" | fzf --multi)
  if [[ -z ${selected_processes} ]]; then
    return
  fi

  local pids=$(print "${selected_processes}" | awk '{print $1}' | xargs echo)
  print -rz -- "kill ${pids}"
}
