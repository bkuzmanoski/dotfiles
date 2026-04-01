export EDITOR="code"
export EZA_CONFIG_DIR="${HOME}/.config/eza"
export FZF_NAVIGATOR_LS_FORMAT="color"
export FZF_NAVIGATOR_LOCK_CWD=1
export FZF_NAVIGATOR_SHOW_HIDDEN=1
export FZF_NAVIGATOR_SHOW_IGNORED=1
export FZF_NAVIGATOR_BINDINGS="left:go_back,right:go_forward"
export FZF_NAVIGATOR_FILE_PREVIEW_COMMAND='if __fzf_navigator_is_binary "${full_path}"; then __fzf_navigator_default_preview_file "${full_path}"; else bat --color=always --style=numbers --theme="$([[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2>/dev/null) == "Dark" ]] && echo "dark" || echo "light")" "${full_path}"; fi; :'
export HOMEBREW_NO_ENV_HINTS=1
export MANPAGER="col -bx | bat --language man --style plain"
export RIPGREP_CONFIG_PATH="${HOME}/.config/ripgrep/ripgreprc"

HISTSIZE=100000

setopt AUTO_CD
setopt ALWAYS_TO_END
setopt COMPLETE_IN_WORD
setopt CORRECT_ALL
setopt GLOB_DOTS
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY

autoload -Uz add-zsh-hook
autoload -Uz compinit && compinit
autoload -Uz undo
autoload -Uz zmv

source "${HOME}/.zsh/prompt.zsh"
source "${HOME}/.zsh/aliases.zsh"
source "${HOME}/.zsh/keybindings.zsh"
source "${HOME}/.zsh/plugins.zsh"
source "${HOME}/.zsh/theme.zsh"

for file in ~/.zsh/{bin,hooks,widgets}/*.zsh; do
  source "${file}"
done

eval "$(zoxide init zsh)"

fnm_use_on_cd
check_last_update_time
