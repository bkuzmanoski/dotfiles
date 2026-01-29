zstyle ":zce:*" prompt-char "Search for character: "
zstyle ":zce:*" prompt-key "Target key: "

function zce-themed() {
  if [[ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]; then
    zstyle ":zce:*" fg "fg=7,bold"
    zstyle ":zce:*" bg "fg=15"
  else
    zstyle ":zce:*" fg "fg=0,bold"
    zstyle ":zce:*" bg "fg=8"
  fi

  zce
}

zle -N zce-themed
