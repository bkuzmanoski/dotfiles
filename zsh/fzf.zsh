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
  local path_type="${1}"
  local selected_paths=("${(@f)$(fd --type "${path_type}" --hidden | fzf --scheme path --multi)}")
  shift

  [[ -z ${selected_paths[@]} ]] && return

  local escaped_paths=("${(q)selected_paths[@]}")
  local prefix_command=("${@}")

  if (( ${#prefix_command[@]} )); then
    print -z -- "${prefix_command[@]} ${escaped_paths[@]}"
  else
    print -rn -- "${escaped_paths[@]}" | pbcopy
    print "Copied to clipboard."
  fi
}

fdir() {
  select_paths d "${@}"
}

ff() {
  select_paths f "${@}"
}

fh() {
  local selected_command=$(fc -nl 1 | tail -r | fzf --scheme history)
  print -z -- "${selected_command}"
}

fk() {
  local selected_processes=$(ps -eo pid,comm | sed -E "1d; s/^([[:space:]]*)([0-9]+)/\2\1/" | fzf --multi)
  if [[ -z ${selected_processes} ]]; then
    return 1
  fi

  local pids=$(print "${selected_processes}" | awk '{print $1}' | xargs echo)
  print -z "kill ${pids}"
}
