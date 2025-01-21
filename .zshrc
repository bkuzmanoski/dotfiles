# Custom prompt
precmd() {
  precmd() {
    echo
  }
}

PROMPT="%F{8}[%f%~%F{8}]%f "

# Shell Options
setopt auto_cd # Automatically cd into a directory if the command is a directory
setopt hist_ignore_dups # Ignore duplicate commands in history
setopt hist_ignore_space # Ignore commands starting with a space in history

# Tools configuration
export EDITOR="micro"
export MANPAGER="sh -c 'col -bx | bat -l man -p'" # Use bat for man pages

export EZA_CONFIG_DIR="${HOME}/.config/eza/"
eza_opts="--all --group-directories-first --oneline"

eval "$(fzf --zsh)"
fzf_walker_skip_opts=".git,Containers,Daemon\ Containers,Group\ Containers,Mobile\ Documents,Movies,Music,Pictures,System"
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
  "--color=fg:#b4bbc2,hl:#61abda"
  "--color=fg+:#b4bbc2,bg+:#395263,hl+:#61abda"
  "--color=spinner:#839099,info:#cf86c1,marker:#61abda"
  "--color=scrollbar:#637079,border:#637079"
)
export FZF_COMPLETION_DIR_OPTS=(
  "--walker=dir,hidden"
  "--walker-skip=${fzf_walker_skip_opts}"
  "--preview='eza ${eza_opts} --color=always {}'"
)
export FZF_COMPLETION_PATH_OPTS=(
  "--walker=file,hidden"
  "--walker-skip=${fzf_walker_skip_opts},node_modules"
  "--preview='bat --style=numbers --color=always {}'"
)
export FZF_CTRL_T_OPTS=(
  "--walker=file,hidden"
  "--walker-skip=${fzf_walker_skip_opts},node_modules"
  "--preview='bat --style=numbers --color=always {}'"
)
export FZF_ALT_C_OPTS=(
  "--walker=dir,hidden"
  "--walker-skip=${fzf_walker_skip_opts}"
  "--preview='eza ${eza_opts} --color=always {}'"
)
export FZF_CTRL_R_OPTS=(
  "--scheme=history"
  "--bind='ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'"
)

export MICRO_TRUECOLOR=1 # Enable true color support in micro

# Plugins
autoload -Uz compinit
compinit

setopt always_to_end # Move cursor to the end of the line when autocompleting
setopt complete_in_word # Enable autocompletion in the middle of a word

_comp_options+=(globdots) # Include dotfiles in autocompletion

zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case-insensitive completion
zstyle ':completion:*' rehash true # Automatically find new executables in PATH

if [[ -f "$HOME/.zsh/fzf-tab/fzf-tab.plugin.zsh" ]]; then
  source "$HOME/.zsh/fzf-tab/fzf-tab.plugin.zsh"

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

# Syntax highlighting to match Zenith theme
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
alias cat="bat"
alias cp="cp -iv" # Prompt before overwriting (-i) and show what's being copied (-v)
alias ls="eza ${eza_opts}"
alias lt="eza ${eza_opts} --tree --level=3"
alias mv="mv -iv" # Prompt before overwriting (-i) and show what's being moved (-v)
alias mkdir="mkdir -pv" # Create parent directories as needed (-p) and show what's being created (-v)
alias rm="rm -iv" # Confirm deletion of files (-i) and show what's being deleted (-v)
alias -g -- --help="--help 2>&1 | bat --language=help --style=plain" # Global alias: pipe any --help output through bat with help syntax highlighting

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
  local thirty_days=2592000

  [[ ! -d "${timestamp_dir}" ]] && mkdir -p "${timestamp_dir}"

  for check in "${update_checks[@]}"; do
  local IFS=":"
  local parts=(${=check})

  local emoji="${parts[1]}"
  local description="${parts[2]}"
  local timestamp_file="${parts[3]}"
  local command="${parts[4]}"

  local last_update=0
  [[ -f "${timestamp_file}" ]] && last_update="$(<"${timestamp_file}")"

  local time_diff="$((now - last_update))"

  if (( time_diff > thirty_days )); then
    echo
    echo "It's been a month since your last ${description} update! ${emoji}"
    echo "Run: ${command}"
  fi
  done
}

check_update_timestamps

brewup() {
  local current_dir="${PWD}"
  cd ~/.dotfiles || return 1

  {
    brew update || { echo "brew update failed"; return 1; }
    brew upgrade || { echo "brew upgrade failed"; return 1; }
    brew bundle || { echo "brew bundle failed"; return 1; }
    brew autoremove || { echo "brew autoremove failed"; return 1; }
    brew cleanup || { echo "brew cleanup failed"; return 1; }

    date +%s > "${timestamp_dir}/brew_last_update"
    echo "brew update timestamp updated, next reminder in 30 days"
  } always {
    cd "${current_dir}"
  }
}

fnmup() {
  set -e
  set -u

  local current_version="$(fnm current)"
  local latest_version="$(fnm ls-remote --lts | tail -n1 | cut -d' ' -f1)" || {
    echo "Failed to fetch latest Node version"
    return 1
  }
  [[ -z "${latest_version}" ]] && {
    echo "No LTS versions found"
    return 1
  }

  echo "Current version: ${current_version}"
  echo "Latest version: ${latest_version}"
  echo
  if [[ "${current_version}" != "${latest_version}" ]]; then
  echo "New version available!"
  read -r "response?Install latest version? (y/N) "
  if [[ "${response}" =~ ^[Yy]$ ]]; then
    fnm install "${latest_version}" || {
      echo "Failed to install Node ${latest_version}"
      return 1
    }
    echo
    read -r "default?Set as default? (y/N) "
    if [[ "${default}" =~ ^[Yy]$ ]]; then
      fnm default "${latest_version}" || {
      echo "Failed to set Node.js ${latest_version} as default"
      return 1
      }
      echo "Node ${latest_version} is now default"
    fi
    echo
    read -r "cleanup?Clean up old versions? (y/N) "
    if [[ "${cleanup}" =~ ^[Yy]$ ]]; then
      local installed_versions="$(fnm ls | grep -v 'system' | grep -v "${latest_version}" | tr -d '* ' | grep -o 'v[0-9][0-9.]*')"
      if [[ -n "${installed_versions}" ]]; then
      echo "The following versions will be removed:"
      echo "${installed_versions}"
      echo
      read -r "confirm?Proceed? (y/N) "
      if [[ "${confirm}" =~ ^[Yy]$ ]]; then
        echo "${installed_versions}" | while read -r version; do
          if [[ -n "${version}" ]]; then
          printf "Removing %s...\n" "${version}"
          fnm uninstall "${version}" || {
            echo "Failed to remove Node ${version}"
            return 1
          }
          fi
        done
        echo
        echo "Cleanup complete!"
      fi
      else
      echo "No old versions to clean up"
      fi
    fi
  fi
  else
    echo "You're up to date!"
  fi

  date +%s > "${timestamp_dir}/fnm_last_update"
  echo "fnm update timestamp updated, next reminder in 30 days"
}

ftup() {
  local current_dir="${PWD}"
  local fzf_tab_dir="$HOME/.zsh/fzf-tab"

  {
    if [[ ! -d "$fzf_tab_dir" ]]; then
      mkdir -p "$HOME/.zsh"
      git clone https://github.com/Aloxaf/fzf-tab "$fzf_tab_dir" || { echo "fzf-tab installation failed"; return 1; }

      date +%s > "${timestamp_dir}/fzf_tab_last_update"
      echo "fzf-tab installed, restart shell to use it"
    else
      (cd "$fzf_tab_dir" && git pull) || { echo "fzf-tab update failed"; return 1; }

      date +%s > "${timestamp_dir}/fzf_tab_last_update"
      echo "fzf-tab update timestamp updated, next reminder in 30 days"
    fi
  } always {
    cd "${current_dir}"
  }
}
