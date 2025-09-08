precmd() {
  precmd() {
    print
  }
}

PROMPT="%F{8}[%f%~%F{8}]%f "

setopt AUTO_CD
setopt CORRECT_ALL
setopt GLOB_DOTS
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY
setopt ALWAYS_TO_END
setopt COMPLETE_IN_WORD

export EDITOR="micro"
export EZA_CONFIG_DIR="${HOME}/.config/eza"
export MANPAGER="col -bx | bat --language man --style plain"
export MICRO_TRUECOLOR=1
export RIPGREP_CONFIG_PATH="${HOME}/.config/ripgrep/ripgreprc"

alias ..="cd .."
alias ...="cd ../.."
alias -- --='cd - >/dev/null'
alias cdd="cd ~/Downloads"
alias cdp="cd ~/Developer"
alias ls="eza --all --group-directories-first --oneline"
alias lt="eza --all --group-directories-first --tree --level 3"
alias ll="eza --all --group-directories-first --header --long --no-permissions --no-user"
alias llt="eza --all --group-directories-first --header --long --no-permissions --no-user --tree --level 3"
alias mkdir="mkdir -pv"
alias mv="mv -i"
alias cp="cp -iv"
alias rm="rm -i"
alias fd="fd --hidden --no-ignore-vcs --color never"
alias cat="bat"
alias micro="update_theme && micro --colorscheme \"\${THEME}\""
alias p2j="plutil -convert json -o -"
alias p2x="plutil -convert xml1 -o -"
alias top="top -s 1 -S -stats pid,command,cpu,th,mem,purg,user,state"

autoload -Uz compinit; compinit

source ~/.zsh/plugins.zsh
source ~/.zsh/theme.zsh
for file in ~/.zsh/utils/*.zsh; do
  source "${file}"
done
