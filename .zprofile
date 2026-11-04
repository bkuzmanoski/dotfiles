eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(fnm env --shell zsh)"

export ANDROID_HOME="${HOMEBREW_PREFIX}/share/android-commandlinetools"

typeset -U path=("${HOME}/.dotfiles/bin" "${HOME}/.dotfiles/utils/bin" "${HOME}/.cargo/bin" "${HOMEBREW_PREFIX}/opt/rustup/bin" "${ANDROID_HOME}/emulator" "${ANDROID_HOME}/platform-tools" "${path[@]}")
