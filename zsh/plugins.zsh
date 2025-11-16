typeset -A PLUGINS=(
  # [plugin]=git_url|source_file
  ["fzf-tab"]="https://github.com/Aloxaf/fzf-tab|fzf-tab.plugin.zsh"
  ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions|zsh-autosuggestions.zsh"
  ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting|zsh-syntax-highlighting.zsh"
)

readonly UPDATE_TIMESTAMPS_DIR="${HOME}/.config/zsh"
readonly UPDATE_REMINDERS=(
  # emoji|description|timestamp_file|update_command
  "🍺|brew|${UPDATE_TIMESTAMPS_DIR}/brew_last_update|brewup"
  "📦|fnm|${UPDATE_TIMESTAMPS_DIR}/fnm_last_update|fnmup"
  "🧩|Zsh plugins|${UPDATE_TIMESTAMPS_DIR}/zsh_plugins_last_update|zshup"
)

brewup() (
  cd ~/.dotfiles           || { print ".dotfiles directory not found."; exit 1 }
  brew upgrade             || { print "brew upgrade failed."; exit 1 }
  brew bundle              || { print "brew bundle failed."; exit 1 }
  brew autoremove          || { print "brew autoremove failed."; exit 1 }
  brew cleanup --prune all || { print "brew cleanup failed."; exit 1 }
  _update_timestamps "brew_last_update"
)

fnmup() {
  local current_version="$(fnm current)"
  local latest_version="$(set -o pipefail; fnm ls-remote --lts | tail -n1 | cut -d' ' -f1)"

  if [[ -z "${latest_version}" ]]; then
    print -u2 "Failed to query latest Node LTS version."
    return 1
  fi

  if [[ "${current_version}" != "${latest_version}" ]]; then
    print "Current version: ${current_version}"
    print "Latest version: ${latest_version}"
    print
    read -r "response?Install latest version? (y/N) "

    if [[ "${response}" =~ ^[Yy]$ ]]; then
      fnm install "${latest_version}"

      if [[ $? -ne 0 ]]; then
        print -u2 "\nFailed to install Node ${latest_version}."
        return 1
      fi

      print
      read -r "default?Set as default? (y/N) "

      if [[ "${default}" =~ ^[Yy]$ ]]; then
        fnm default "${latest_version}"

        if [[ $? -ne 0 ]]; then
          print -u2 "\nFailed to set Node ${latest_version} as default."
          return 1
        fi

        print "Node ${latest_version} is now default."
      fi

      print
      read -r "cleanup?Clean up old versions? (y/N) "

      if [[ "${cleanup}" =~ ^[Yy]$ ]]; then
        local installed_versions="$(fnm ls | grep -v "system" | grep -v "${latest_version}" | tr -d "* " | grep -o "v[0-9][0-9.]*")"

        if [[ -n "${installed_versions}" ]]; then
          print "The following version(s) will be removed:"
          print "${installed_versions}"
          print
          read -r "confirm?Proceed? (y/N) "

          if [[ "${confirm}" =~ ^[Yy]$ ]]; then
            print "${installed_versions}" | while read -r version; do
              if [[ -n "${version}" ]]; then
                print "Removing "${version}"...\n"
                fnm uninstall "${version}"

                if [[ $? -ne 0 ]]; then
                  print -u2 "\nFailed to remove Node ${version}."
                  return 1
                fi
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

  _update_timestamps "fnm_last_update"
}

zshup() (
  local plugin_keys=("${(k)PLUGINS[@]}")
  local number_of_plugins=${#plugin_keys[@]}

  if (( ${number_of_plugins} == 0 )); then
    print "No plugins to update."
    return 0
  fi

  for (( i=1; i<=${number_of_plugins}; i++ )); do
    local plugin="${plugin_keys[i]}"
    local plugin_dir="${HOME}/.zsh/${plugin}"

    print -P "Updating %B${plugin}%b...\n"

    (
      cd "${plugin_dir}"
      print -nP '\e[1A\e[2K\r'
      git pull
    )

    if [[ $? -ne 0 ]]; then
      print -u2 "\n${plugin} update failed."
      exit 1
    fi

    if (( i < ${#plugin_keys[@]} )); then
      print
    fi
  done

  _update_timestamps "zsh_plugins_last_update"
)

_source_plugins() {
  local plugins_installed=0

  for plugin in ${(k)PLUGINS[@]}; do
    local target_dir="${HOME}/.zsh/${plugin}"
    local git_repository="${PLUGINS[${plugin}]%%|*}"
    local source_file="${PLUGINS[${plugin}]#*|}"

    if [[ ! -d "${target_dir}" ]]; then
      print -P "Installing %B${plugin}%b..."
      git clone "${git_repository}" "${target_dir}"

      if [[ $? -ne 0 ]]; then
        print -u2 "\n${plugin} installation failed."
        print
        continue
      fi

      plugins_installed=1
      print
    fi

    if [[ -f "${target_dir}/${source_file}" ]]; then
      source "${target_dir}/${source_file}"
    else
      print "Warning: Plugin file ${source_file} not found for ${plugin}\n"
    fi
  done

  if (( plugins_installed )); then
    zshup > /dev/null
  fi
}

_source_plugins

_check_last_update_time() {
  local now="$(date "+%s")"
  local frequency="$(( 7 * 86400 ))"
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

      if [[ ! "${last_update_timestamp}" =~ ^[0-9]+$ ]]; then
        last_update_timestamp=0
      fi
    fi

    local time_diff="$((now - last_update_timestamp))"
    if (( time_diff > frequency )); then
      print -P "${emoji} It's been a month since the last ${description} update! Run: %B${command}%b"
      updates_required=1
    fi
  done

  if (( updates_required )); then
    print
  fi
}

_check_last_update_time

_update_timestamps() {
  if [[ ! -d "${UPDATE_TIMESTAMPS_DIR}" ]]; then
    mkdir -p "${UPDATE_TIMESTAMPS_DIR}" >/dev/null
  fi

  date "+%s" >"${UPDATE_TIMESTAMPS_DIR}/$1"
  print "\nUpdate timestamp updated, next reminder in 30 days."
}
