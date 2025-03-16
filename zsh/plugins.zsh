typeset -A PLUGINS=(
  # Format: [plugin]=git_url|source_file
  ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab|fzf-tab.plugin.zsh"
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions|zsh-autosuggestions.zsh"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting|zsh-syntax-highlighting.zsh"
)

UPDATE_TIMESTAMPS_DIR="${HOME}/.zsh/.update_timestamps"
UPDATE_REMINDERS=(
  # Format: emoji|description|timestamp_file|update_command
  "🍺|brew|${UPDATE_TIMESTAMPS_DIR}/brew_last_update|brewup"
  "📦|fnm|${UPDATE_TIMESTAMPS_DIR}/fnm_last_update|fnmup"
  "🧩|Zsh plugins|${UPDATE_TIMESTAMPS_DIR}/zsh_plugins_last_update|zshup"
)

brewup() (
  cd ~/.dotfiles || { print ".dotfiles directory not found."; exit 1 }
  brew upgrade || { print "brew upgrade failed."; exit 1 }
  brew bundle || { print "brew bundle failed."; exit 1 }
  brew autoremove || { print "brew autoremove failed."; exit 1 }
  brew cleanup --prune all || { print "brew cleanup failed."; exit 1 }

  print
  _update_timestamps "brew_last_update"
)

fnmup() {
  local current_version="$(fnm current)"
  local latest_version="$(fnm ls-remote --lts | tail -n1 | cut -d' ' -f1)" || {
    print "Failed to fetch latest Node version."
    return 1
  }

  if [[ -z "${latest_version}" ]]; then
    print "No LTS versions found."
    return 1
  fi

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

      print && read -r "default?Set as default? (y/N) "
      if [[ "${default}" =~ ^[Yy]$ ]]; then
        fnm default "${latest_version}" || {
          print "Failed to set Node.js ${latest_version} as default."
          return 1
        }
        print "Node ${latest_version} is now default."
      fi

      print && read -r "cleanup?Clean up old versions? (y/N) "
      if [[ "${cleanup}" =~ ^[Yy]$ ]]; then
        local installed_versions="$(fnm ls | grep -v "system" | grep -v "${latest_version}" | tr -d "* " | grep -o "v[0-9][0-9.]*")"
        if [[ -n "${installed_versions}" ]]; then
          print "The following versions will be removed:"
          print "${installed_versions}"

          print && read -r "confirm?Proceed? (y/N) "
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
            print "\nCleanup complete."
          fi
        else
          print "No old versions to clean up."
        fi
      fi
    fi
  else
    print "Already up to date."
  fi

  print
  _update_timestamps "fnm_last_update"
}

zshup() (
  for plugin in "${(k)PLUGINS[@]}"; do
    local plugin_dir="${HOME}/.zsh/${plugin}"
    print -P "Updating %B${plugin}%b..."
    cd "${plugin_dir}" && git pull || { print "${plugin} update failed."; exit 1 }
    print
  done

  _update_timestamps "zsh_plugins_last_update"
)

_source_plugins() {
  local plugins_installed=0
  for plugin in ${(k)PLUGINS[@]}; do
    local target_dir="${HOME}/.zsh/${plugin}"
    local git_repository=${PLUGINS[${plugin}]%%|*}
    local source_file=${PLUGINS[${plugin}]#*|}
    if [[ ! -d "${target_dir}" ]]; then
      print -P "Installing %B${plugin}%b..."
      git clone "${git_repository}" "${target_dir}" || { print "${plugin} installation failed.\n"; continue }
      plugins_installed=1
      print
    fi
    if [[ -f "${target_dir}/${source_file}" ]]; then
      source "${target_dir}/${source_file}"
    else
      print "Warning: Plugin file ${source_file} not found for ${plugin}"
    fi
  done

  (( plugins_installed )) && zshup > /dev/null # Update timestamps
}

_source_plugins

_check_last_update_time() {
  local now="$(date "+%s")"
  local frequency="$((7 * 86400))" # Weekly
  local updates_required=0

  for reminder in "${UPDATE_REMINDERS[@]}"; do
    local parts=("${(@s.|.)reminder}")
    local emoji="${parts[1]}"
    local description="${parts[2]}"
    local timestamp_file="${parts[3]}"
    local command="${parts[4]}"

    local last_update_timestamp=0
    if [[ -f "${timestamp_file}" ]]; then
      last_update_timestamp="$(<"${timestamp_file}")"
      [[ "${last_update_timestamp}" =~ ^[0-9]+$ ]] || last_update_timestamp=0
    fi

    local time_diff="$((now - last_update_timestamp))"
    if (( time_diff > frequency )); then
      print -P "${emoji} It's been a month since the last ${description} update! Run: %B${command}%b"
      updates_required=1
    fi
  done

  (( updates_required )) && print # Print a newline before initial prompt
}

_check_last_update_time

_update_timestamps() {
  [[ ! -d "${UPDATE_TIMESTAMPS_DIR}" ]] && mkdir -p "${UPDATE_TIMESTAMPS_DIR}" >/dev/null
  date "+%s" >"${UPDATE_TIMESTAMPS_DIR}/$1"
  print "Update timestamp updated, next reminder in 30 days."
}
