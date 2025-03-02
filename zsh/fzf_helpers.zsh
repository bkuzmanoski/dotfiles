FZF_OPTS=(
  --height=100%
  --no-separator
  --prompt=""
  --info=inline:""
  --pointer=""
  --marker="✓"
  --marker-multi-line="✓  "
  --highlight-line
  --layout=reverse
  --ellipsis="…"
)

fzf() {
  update_theme && command fzf "${FZF_OPTS[@]}" --color "${FZF_THEME}" "$@"
}

select_paths() {
  local file_type=$1
  shift

  local -a selected_paths=("${(@f)$(fd --type "${file_type}" --hidden | fzf --scheme path --multi)}")
  if [[ -z ${selected_paths[@]} ]]; then
    return 1
  fi

  local -a escaped_paths=("${(q)selected_paths[@]}")
  local delimited_paths="${(j: :)escaped_paths}"

  local -a prefix_command=("$@")
  if (( ${#prefix_command[@]} )); then
    print -z -- "${prefix_command[@]} ${selected_paths[*]}"
  else
    print -rn -- "${delimited_paths}" | pbcopy
    print "Copied to clipboard."
  fi
}

fdir() {
  select_paths d "$@"
}

ff() {
  select_paths f "$@"
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
