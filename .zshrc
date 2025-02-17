# Custom prompt
precmd() {
  precmd() {
    print
  }
}

PROMPT="%F{8}[%f%~%F{8}]%f "

# Shell options
setopt AUTO_CD # Automatically cd into a directory if the command is a directory
setopt GLOB_DOTS # Include hidden files in globbing
setopt HIST_IGNORE_DUPS # Ignore duplicate commands in history
setopt HIST_IGNORE_SPACE # Ignore commands starting with a space in history
setopt SHARE_HISTORY # Share history across all sessions

# Tools configuration
export EDITOR="micro"
export MANPAGER="col -bx | bat --language=man --style=plain" # Use bat for man pages

export EZA_CONFIG_DIR="${HOME}/.config/eza"

eval "$(fzf --zsh)"
fzf_walker_skip_opts=".git,Containers,Daemon\ Containers,Group\ Containers,Mobile\ Documents,Movies,Music,Pictures,System"
fzf () {
  update_theme

  if [[ ${THEME} = "zenith"* ]]; then
    local theme_colors="bg+:#395263,border:8,scrollbar:8"
  else
    local theme_colors="bg+:#b2c9d8,border:15,scrollbar:15"
  fi

  command fzf "--color=${theme_colors}" "$@"
}
export FZF_DEFAULT_OPTS=(
  "--height=100%"
  "--color=gutter:-1"
  "--no-separator"
  "--prompt=''"
  "--info=inline:''"
  "--pointer=''"
  "--marker='✓'"
  "--marker-multi-line='✓  '"
  "--highlight-line"
  "--wrap"
  "--wrap-sign='  '"
  "--preview-window hidden"
  "--bind 'ctrl-p:toggle-preview'"
  "--color=fg:-1,fg+:-1,bg:-1,hl:4,hl+:4,info:5,marker:4"
)
export FZF_COMPLETION_DIR_OPTS=(
  "--walker=dir,hidden"
  "--walker-skip=${fzf_walker_skip_opts}"
  "--preview='eza --all --color=always --group-directories-first --oneline {}'"
)
export FZF_COMPLETION_PATH_OPTS=(
  "--walker=file,hidden"
  "--walker-skip=${fzf_walker_skip_opts},node_modules"
  "--preview='bat --color=always --italic-text=always --style=plain {}'"
)
export FZF_CTRL_T_OPTS=(
  "--walker=file,hidden"
  "--walker-skip=${fzf_walker_skip_opts},node_modules"
  "--preview='bat --color=always --italic-text=always --style=plain {}'"
)
export FZF_ALT_C_OPTS=(
  "--walker=dir,hidden"
  "--walker-skip=${fzf_walker_skip_opts}"
  "--preview='eza --all --color=always --group-directories-first --oneline {}'"
)
export FZF_CTRL_R_OPTS=(
  "--scheme=history"
  "--bind='ctrl-y:execute-silent(print -n {2..} | pbcopy)+abort'"
)

export MICRO_TRUECOLOR=1 # Enable true color support in micro

# Plugins
autoload -Uz compinit
compinit

setopt always_to_end # Move cursor to the end of the line when autocompleting
setopt complete_in_word # Enable autocompletion in the middle of a word

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case-insensitive completion
zstyle ':completion:*' rehash true # Automatically find new executables in PATH

if [[ -f "${HOME}/.zsh/fzf-tab/fzf-tab.plugin.zsh" ]]; then
  source "${HOME}/.zsh/fzf-tab/fzf-tab.plugin.zsh"

  zstyle ':completion:*' menu no # Disable completion menu since fzf-tab will handle it
  zstyle ':completion:*:git-checkout:*' sort false # Disable sorting for git-checkout

  zstyle ':fzf-tab:*' continuous-trigger '/' # Use '/' key to trigger continuous completion
  zstyle ':fzf-tab:*' switch-group ',' '.' # Use ',' and '.' keys to switch between completion groups
  zstyle ':fzf-tab:*' use-fzf-default-opts yes # Use FZF_DEFAULT_OPTS for fzf-tab
else
  setopt auto_menu
  zstyle ':completion:*' menu select # Enable completion menu (if fzf-tab is not available)
fi

source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

ZSH_HIGHLIGHT_STYLES[alias]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[arg0]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[autodirectory]="fg=7,underline"
ZSH_HIGHLIGHT_STYLES[back-dollar-quoted-argument]="fg=5"
ZSH_HIGHLIGHT_STYLES[back-double-quoted-argument]="fg=5"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=5,bold"
ZSH_HIGHLIGHT_STYLES[command]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[comment]="fg=8"
ZSH_HIGHLIGHT_STYLES[dollar-double-quoted-argument]="fg=5"
ZSH_HIGHLIGHT_STYLES[double-hyphen-option]="fg=3"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=2"
ZSH_HIGHLIGHT_STYLES[function]="fg=4,bold"
ZSH_HIGHLIGHT_STYLES[global-alias]="fg=3"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=15"
ZSH_HIGHLIGHT_STYLES[path]="none"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=5"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=5"
ZSH_HIGHLIGHT_STYLES[reserved-word]="fg=5"
ZSH_HIGHLIGHT_STYLES[single-hyphen-option]="fg=3"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=2"
ZSH_HIGHLIGHT_STYLES[suffix-alias]="fg=7,underline"
ZSH_HIGHLIGHT_STYLES[unknown-token]="fg=1,bold"

# Aliases
alias ..="cd .."
alias ...="cd ../.."
alias cat="update_theme && bat --italic-text=always"
alias cp="cp -iv"
alias ll="eza --all --group-directories-first --header --long --no-permissions --no-user"
alias llt="eza --all --group-directories-first --header --long --no-permissions --no-user --tree --level=3"
alias ls="eza --all --group-directories-first --oneline"
alias lt="eza --all --group-directories-first --tree --level=3"
alias man="update_theme && man"
alias micro="update_theme && micro --colorscheme=\${THEME}"
alias mkdir="mkdir -pv"
alias mv="mv -iv"
alias rm="rm -iv"
alias top="top -s 5 -S -stats pid,command,cpu,th,mem,purg,user,state"

# Helper function to update theme variables
update_theme() {
  macos_theme=$(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null)

  # Set theme environment variable based on macOS setting
  if [[ ${macos_theme} == "Dark" ]]; then
    export THEME="zenith-neutral"
  else
    export THEME="meridian-neutral"
  fi

  export BAT_THEME="${THEME}"
}

update_theme

# Update reminders
timestamp_dir="${HOME}/.update_timestamps"
update_checks=(
  # Format: [emoji]:[description]:[timestamp_file]:[update_command]
  "🍺:brew:${timestamp_dir}/brew_last_update:brewup"
  "📦:fnm:${timestamp_dir}/fnm_last_update:fnmup"
  "🔍:fzf-tab:${timestamp_dir}/fzf_tab_last_update:ftup"
)

check_update_timestamps() {
  local now="$(date +%s)"
  local thirty_days=$((30 * 86400)) # 30 days in seconds
  local updates_required=0

  [[ ! -d "${timestamp_dir}" ]] && mkdir -p "${timestamp_dir}" >&/dev/null

  for check in "${update_checks[@]}"; do
    local parts=("${(@s.:.)check}")
    local emoji="${parts[1]}"
    local description="${parts[2]}"
    local timestamp_file="${parts[3]}"
    local command="${parts[4]}"

    local last_update=0
    if [[ -f "${timestamp_file}" ]]; then
      last_update="$(<"${timestamp_file}")"
      [[ "${last_update}" =~ ^[0-9]+$ ]] || last_update=0
    fi

    local time_diff="$((now - last_update))"

    if (( time_diff > thirty_days )); then
      print -P "${emoji} It's been a month since your last %B${description}%b update! Run: %B%F{4}${command}%f%b."
      updates_required=1
    fi
  done

  (( updates_required )) && print
}

check_update_timestamps

# Update functions
brewup() (
  cd ~/.dotfiles || { print ".dotfiles directory not found."; exit 1; }

  brew upgrade || { print "brew upgrade failed."; exit 1; }
  brew bundle || { print "brew bundle failed."; exit 1; }
  brew autoremove || { print "brew autoremove failed."; exit 1; }
  brew cleanup || { print "brew cleanup failed."; exit 1; }

  date +%s > "${timestamp_dir}/brew_last_update"
  print "brew update timestamp updated, next reminder in 30 days."
)

fnmup() {
  set -e
  set -u

  local current_version="$(fnm current)"
  local latest_version="$(fnm ls-remote --lts | tail -n1 | cut -d' ' -f1)" || {
    print "Failed to fetch latest Node version."
    return 1
  }
  [[ -z "${latest_version}" ]] && {
    print "No LTS versions found."
    return 1
  }

  if [[ "${current_version}" != "${latest_version}" ]]; then
    print "Current version: ${current_version}"
    print "Latest version: ${latest_version}"
    print
    print "New version available!"
    read -r "response?Install latest version? (y/N) "
    if [[ "${response}" =~ ^[Yy]$ ]]; then
      fnm install "${latest_version}" || {
        print "Failed to install Node ${latest_version}."
        return 1
      }
      print
      read -r "default?Set as default? (y/N) "
      if [[ "${default}" =~ ^[Yy]$ ]]; then
        fnm default "${latest_version}" || {
          print "Failed to set Node.js ${latest_version} as default."
          return 1
        }
        print "Node ${latest_version} is now default."
      fi
      print
      read -r "cleanup?Clean up old versions? (y/N) "
      if [[ "${cleanup}" =~ ^[Yy]$ ]]; then
        local installed_versions="$(fnm ls | grep -v 'system' | grep -v "${latest_version}" | tr -d '* ' | grep -o 'v[0-9][0-9.]*')"
        if [[ -n "${installed_versions}" ]]; then
          print "The following versions will be removed:"
          print "${installed_versions}"
          print
          read -r "confirm?Proceed? (y/N) "
          if [[ "${confirm}" =~ ^[Yy]$ ]]; then
            print "${installed_versions}" | while read -r version; do
              if [[ -n "${version}" ]]; then
                printf "Removing %s...\n" "${version}"
                fnm uninstall "${version}" || {
                  print "Failed to remove Node ${version}."
                  return 1
                }
              fi
            done
            print
            print "Cleanup complete!"
          fi
        else
          print "No old versions to clean up."
        fi
      fi
    fi
  else
    print "Already up to date."
  fi

  date +%s > "${timestamp_dir}/fnm_last_update"
  print "fnm update timestamp updated, next reminder in 30 days."
}

ftup() (
  local fzf_tab_dir="${HOME}/.zsh/fzf-tab"

  if [[ ! -d "${fzf_tab_dir}" ]]; then
    mkdir -p "${HOME}/.zsh"
    git clone https://github.com/Aloxaf/fzf-tab "$fzf_tab_dir" || { print "fzf-tab installation failed."; exit 1; }

    date +%s > "${timestamp_dir}/fzf_tab_last_update"
    print "fzf-tab installed, restart shell to use it."
  else
    (cd "${fzf_tab_dir}" && git pull) || { print "fzf-tab update failed."; exit 1; }

    date +%s > "${timestamp_dir}/fzf_tab_last_update"
    print "fzf-tab update timestamp updated, next reminder in 30 days."
  fi
)
