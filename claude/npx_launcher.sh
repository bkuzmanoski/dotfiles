#!/bin/zsh

# Homebrew -> FNM
eval "$(/opt/homebrew/bin/brew shellenv)"

# FNM -> Node/NPX
eval "$(fnm env)"

exec npx "$@"