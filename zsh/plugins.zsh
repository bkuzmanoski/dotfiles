typeset -A PLUGINS=(
  ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab"
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting"
)
UPDATE_TIMESTAMPS_DIR="${HOME}/.zsh/.update_timestamps"
UPDATE_REMINDERS=(
  # Format: [emoji]:[description]:[timestamp_file]:[update_command]
  "🍺:brew:${UPDATE_TIMESTAMPS_DIR}/brew_last_update:brewup"
  "📦:fnm:${UPDATE_TIMESTAMPS_DIR}/fnm_last_update:fnmup"
  "🧩:Zsh plugins:${UPDATE_TIMESTAMPS_DIR}/zsh_plugins_last_update:zshup"
)

if [[ ! -d "${UPDATE_TIMESTAMPS_DIR}" ]]; then
  mkdir -p "${UPDATE_TIMESTAMPS_DIR}" >/dev/null
  date +%s >"${UPDATE_TIMESTAMPS_DIR}/zsh_plugins_last_update" # Assume first run, plugin installation to follow
fi

install_plugins() {
  for plugin in "${(k)PLUGINS[@]}"; do
    local target_path="${HOME}/.zsh/${plugin}"
    local git_repository="${PLUGINS[${plugin}]}"

    if [[ ! -d "${target_path}" ]]; then
      print -P "Installing %B${plugin}%b..."
      git clone "${git_repository}" "${target_path}" || { print "${plugin} installation failed.\n"; }
      print
    fi
  done
}

install_plugins

check_last_update() {
  local now="$(date +%s)"
  local thirty_days="$((30 * 86400))" # 30 days in seconds
  local updates_required=0

  for reminder in "${UPDATE_REMINDERS[@]}"; do
    local parts=("${(@s.:.)reminder}")
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

check_last_update

brewup() (
  cd ~/.dotfiles || { print ".dotfiles directory not found."; exit 1; }

  brew upgrade || { print "brew upgrade failed."; exit 1; }
  brew bundle || { print "brew bundle failed."; exit 1; }
  brew autoremove || { print "brew autoremove failed."; exit 1; }
  brew cleanup --prune all || { print "brew cleanup failed."; exit 1; }

  date +%s >"${UPDATE_TIMESTAMPS_DIR}/brew_last_update"
  print "brew update timestamp updated, next reminder in 30 days."
)

fnmup() {
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

  date +%s >"${UPDATE_TIMESTAMPS_DIR}/fnm_last_update"
  print "fnm update timestamp updated, next reminder in 30 days."
}

zshup() (
  for plugin in "${(k)PLUGINS[@]}"; do
    local plugin_path="${HOME}/.zsh/${plugin}"
    print -P "Updating %B${plugin}%b..."
    cd "${plugin_path}" && git pull || { print "${plugin} update failed."; exit 1; }
    print
  done

  date +%s >"${UPDATE_TIMESTAMPS_DIR}/zsh_plugins_last_update"
  print "Zsh plugins update timestamp updated, next reminder in 30 days."
)
