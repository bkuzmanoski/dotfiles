#!/bin/zsh

# @raycast.title Unmount DMGs
# @raycast.packageName Finder
# @raycast.icon icons/unmount-dmgs.png
# @raycast.mode silent
# @raycast.schemaVersion 1

source "${HOME}/.dotfiles/zsh/utils/udmg.zsh"

if ! udmg >/dev/null 2>&1; then
  print "Failed to unmount DMGs."
  exit 1
fi
