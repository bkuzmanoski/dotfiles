eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(fnm env --shell zsh)"

typeset -U path=("${HOME}/.dotfiles/bin" "${HOME}/.dotfiles/utils/bin" "${HOME}/.cargo/bin" "${HOMEBREW_PREFIX}/opt/rustup/bin" "${path[@]}")
