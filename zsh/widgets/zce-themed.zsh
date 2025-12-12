zstyle ":zce:*" prompt-char "Search for character: "
zstyle ":zce:*" prompt-key "Target key: "

zce-themed() {
  update_theme
  zce
}

zle -N zce-themed
