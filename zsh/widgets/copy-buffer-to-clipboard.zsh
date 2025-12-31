copy-buffer-to-clipboard() {
  print -n "${BUFFER}" | pbcopy
  zle -M "Copied to clipboard"
}

zle -N copy-buffer-to-clipboard
