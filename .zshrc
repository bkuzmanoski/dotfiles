precmd() {
  precmd() {
    print
  }
}

PROMPT="%F{8}[%f%~%F{8}]%f "
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
export MICRO_TRUECOLOR=1
export RIPGREP_CONFIG_PATH="${HOME}/.config/ripgrep/ripgreprc"
export ZSH_AI_CMD_KEY='\ea'

alias -- --='cd - >/dev/null'
alias ...="cd ../.."
alias ..="cd .."
alias cat="bat"
alias cdc="cd ~/.dotfiles"
alias cdd="cd ~/Downloads"
alias cdh="cd ~"
alias cdp="cd ~/Developer"
alias cp="cp -iv"
alias fd="fd --hidden --no-ignore-vcs --color never"
alias ll="eza --all --group-directories-first --header --long --no-permissions --no-user"
alias llt="eza --all --group-directories-first --header --long --no-permissions --no-user --tree --level 3"
alias ls="eza --all --group-directories-first --oneline"
alias lt="eza --all --group-directories-first --tree --level 3"
alias micro="update_theme && micro --colorscheme \"\${THEME}\""
alias mkdir="mkdir -pv"
alias mv="mv -i"
alias p2j="plutil -convert json -o -"
alias p2x="plutil -convert xml1 -o -"
alias rm="rm -i"
alias top="top -s 1 -S -stats pid,command,cpu,th,mem,purg,user,state"

autoload -Uz compinit
compinit

source "${HOME}/.zsh/plugins.zsh"
source "${HOME}/.zsh/theme.zsh"

for file in ~/.zsh/{utils,widgets}/*.zsh; do
  source "${file}"
done

bindkey "\eg" zce-themed
