HISTSIZE=100000

setopt AUTO_CD
setopt ALWAYS_TO_END
setopt COMPLETE_IN_WORD
setopt CORRECT_ALL
setopt GLOB_DOTS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY

export EDITOR="code"
export EZA_CONFIG_DIR="${HOME}/.config/eza"
export HOMEBREW_NO_ENV_HINTS=1
export MANPAGER="col -bx | bat --language man --style plain"
export RIPGREP_CONFIG_PATH="${HOME}/.config/ripgrep/ripgreprc"

autoload -Uz compinit && compinit
autoload -Uz undo
autoload -Uz zmv

source "${HOME}/.zsh/prompt.zsh"
source "${HOME}/.zsh/aliases.zsh"
source "${HOME}/.zsh/plugins.zsh"
source "${HOME}/.zsh/keybindings.zsh"
source "${HOME}/.zsh/theme.zsh"

for file in ~/.zsh/{bin,widgets}/*.zsh; do
  source "${file}"
done

