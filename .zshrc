export EDITOR="micro"
export EZA_CONFIG_DIR="${HOME}/.config/eza"
export MANPAGER="col -bx | bat --language man --style plain" # Use bat for man pages
export MICRO_TRUECOLOR=1

alias ..="cd .."
alias ...="cd ../.."
alias cat="bat"
alias cp="cp -iv"
alias fd="fd --hidden --no-ignore-vcs --color never"
alias ll="eza --all --group-directories-first --header --long --no-permissions --no-user"
alias llt="eza --all --group-directories-first --header --long --no-permissions --no-user --tree --level=3"
alias ls="eza --all --group-directories-first --oneline"
alias lt="eza --all --group-directories-first --tree --level 3"
alias micro="update_theme && micro --colorscheme \${THEME}"
alias mkdir="mkdir -pv"
alias mv="mv -i"
alias rm="rm -i"
alias top="top -s 5 -S -stats pid,command,cpu,th,mem,purg,user,state"

setopt AUTO_CD           # Automatically cd into a directory if the command is a directory
setopt GLOB_DOTS         # Include hidden files in globbing
setopt HIST_IGNORE_DUPS  # Ignore duplicate commands in history
setopt HIST_IGNORE_SPACE # Ignore commands starting with a space in history
setopt SHARE_HISTORY     # Share history across all sessions
setopt ALWAYS_TO_END     # Move cursor to the end of the line when autocompleting
setopt COMPLETE_IN_WORD  # Enable autocompletion in the middle of a word

autoload -Uz compinit; compinit

source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source "${HOME}/.zsh/plugins.zsh"
source "${HOME}/.zsh/theme.zsh"
source "${HOME}/.zsh/fzf_helpers.zsh"
source "${HOME}/.zsh/fzf-tab/fzf-tab.plugin.zsh"
source "${HOME}/.zsh/gh_copilot.zsh"

zstyle ":completion:*" matcher-list "m:{a-zA-Z}={A-Za-z}" # Case-insensitive completion
zstyle ":completion:*" rehash true                        # Automatically find new executables in PATH
zstyle ":completion:*" menu no                            # Disable completion menu since fzf-tab will handle it
zstyle ":completion:*:git-checkout:*" sort false          # Disable sorting for git-checkout
zstyle ":fzf-tab:*" continuous-trigger "/"                # Use '/' key to trigger continuous completion

precmd() {
  precmd() {
    print # Add an empty line before the prompt, except for the first prompt
  }
}

PROMPT="%F{8}[%f%~%F{8}]%f "
