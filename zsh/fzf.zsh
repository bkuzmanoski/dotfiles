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
  update_theme && command fzf "${FZF_OPTS[@]}" --color "${FZF_THEME}" "$@"
}

