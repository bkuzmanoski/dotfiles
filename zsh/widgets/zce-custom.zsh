zce-custom() {
  if [[ "$(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null)" == "Dark" ]]; then
    zstyle ":zce:*" fg "fg=7,bold"
    zstyle ":zce:*" bg "fg=15"
  else
    zstyle ":zce:*" fg "fg=0,bold"
    zstyle ":zce:*" bg "fg=8"
  fi

  zce
}

zle -N zce-custom
