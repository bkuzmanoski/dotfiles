fzf_opts=(
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
  update_theme && command fzf "${fzf_opts[@]}" --color="${FZF_THEME}" "$@"
}

select_paths() {
  local -a selections=("${(@f)$("$@" | fzf --scheme=path --multi)}")
  local -a escaped_selections=("${(q)selections[@]}")
  local delimited_selections="${(j: :)escaped_selections}"
  print -rn -- "${delimited_selections}" | pbcopy
}

fdir() {
  select_paths fd --type d --hidden
}

ffile() {
  select_paths fd --type f --hidden
}

fhist() {
  local selected_command=$(fc -nl 1 | tail -r | fzf --scheme=history)
  printf "%b" "${selected_command}" | pbcopy
}

fproc() {
  local selected_line=$(ps -eo pid,comm | sed -E "1d; s/^([[:space:]]*)([0-9]+)/\2\1/" | fzf)
  local pid=$(print "${selected_line}" | awk '{print $1}')
  printf "%s" "${pid}" | pbcopy
}
