precmd() {
  precmd() {
    print
  }
}

PROMPT="%F{8}[%f%~%F{8}]%f "

export EDITOR="micro"
export EZA_CONFIG_DIR="${HOME}/.config/eza"
export MANPAGER="col -bx | bat --language man --style plain"
export MICRO_TRUECOLOR=1

setopt AUTO_CD
setopt GLOB_DOTS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt ALWAYS_TO_END
setopt COMPLETE_IN_WORD

alias ..="cd .."
alias ...="cd ../.."
alias ls="eza --all --group-directories-first --oneline"
alias lt="eza --all --group-directories-first --tree --level 3"
alias ll="eza --all --group-directories-first --header --long --no-permissions --no-user"
alias llt="eza --all --group-directories-first --header --long --no-permissions --no-user --tree --level=3"
alias fd="fd --hidden --no-ignore-vcs --color never"
alias mkdir="mkdir -pv"
alias cp="cp -iv"
alias mv="mv -i"
alias rm="rm -i"
alias cat="bat"
alias micro="update_theme && micro --colorscheme \${THEME}"
alias top="top -s 5 -S -stats pid,command,cpu,th,mem,purg,user,state"

autoload -Uz compinit; compinit

source ~/.zsh/plugins.zsh
source ~/.zsh/fzf.zsh
source ~/.zsh/fzf-tab/fzf-tab.plugin.zsh
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/theme.zsh
