readonly UPDATE_TIMESTAMPS_DIR="${HOME}/.config/zsh"
readonly UPDATE_REMINDER_FREQUENCY_DAYS=30
readonly UPDATE_TASKS=(
  # emoji|description|timestamp_file|update_command
  "🧩|zsh plugins|${UPDATE_TIMESTAMPS_DIR}/zsh_plugins_last_update|zshup"
  "🍺|brew|${UPDATE_TIMESTAMPS_DIR}/brew_last_update|brewup"
  "🟢|fnm|${UPDATE_TIMESTAMPS_DIR}/fnm_last_update|fnmup"
  "📦|cargo packages|${UPDATE_TIMESTAMPS_DIR}/cargo_last_update|cargoup"
)

function _update_timestamps() {
  if [[ ! -d "${UPDATE_TIMESTAMPS_DIR}" ]]; then
    mkdir -p "${UPDATE_TIMESTAMPS_DIR}" >/dev/null
  fi

  date "+%s" >"${UPDATE_TIMESTAMPS_DIR}/$1"
  print "\nUpdate timestamp updated, next reminder in ${UPDATE_REMINDER_FREQUENCY_DAYS} days."
}

function check_last_update_time() {
  local now="$(date "+%s")"
  local frequency="$((UPDATE_REMINDER_FREQUENCY_DAYS * 24 * 60 * 60))"
  local updates_required=0

  for update_task in "${UPDATE_TASKS[@]}"; do
    local parts=("${(@s:|:)update_task}")
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

    local time_since_last_update="$((now - last_update_timestamp))"

    if (( time_since_last_update > frequency )); then
      print -P "${emoji} It's been a month since the last ${description} update! Run: %B${command}%b"
      ((updates_required++))
    fi
  done

  if (( updates_required )); then
    if (( updates_required > 1 )); then
      print -P "\nRun %Bup%b to update all."
    fi

    print
  fi
}

function zshup() (
  local number_of_plugins=${#ZSH_PLUGINS[@]}

  if (( ${number_of_plugins} == 0 )); then
    print "No plugins to update."
    return 0
  fi

  for (( i=1; i<=${number_of_plugins}; i++ )); do
    local plugin_entry="${ZSH_PLUGINS[i]}"
    local parts=("${(@s:|:)plugin_entry}")
    local plugin="${parts[1]}"
    local plugin_dir="${HOME}/.zsh/plugins/${plugin}"

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

    if (( i < ${number_of_plugins} )); then
      print
    fi
  done

  _update_timestamps "zsh_plugins_last_update"
)

function brewup() (
  if ! cd ~/.dotfiles; then
    print ".dotfiles directory not found."
    exit 1
  fi

  brew upgrade || { print "\nbrew upgrade failed."; exit 1 }
  brew bundle || { print "\nbrew bundle failed."; exit 1 }
  brew autoremove || { print "\nbrew autoremove failed."; exit 1 }
  brew cleanup --prune all || { print "\nbrew cleanup failed."; exit 1 }

  _update_timestamps "brew_last_update"
)

function fnmup() {
  local current_version="$(fnm current)"
  local latest_version="$(set -o pipefail; fnm ls-remote --lts | tail -n1 | cut -d' ' -f1)"

  if [[ -z "${latest_version}" ]]; then
    print -u2 "Failed to query latest Node LTS version."
    return 1
  fi

  if [[ "${current_version}" != "${latest_version}" ]]; then
    print "Current version: ${current_version}"
    print "Latest version: ${latest_version}\n"

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
          print "${installed_versions}\n"

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

function cargoup() {
  if ! cargo install-update -a; then
    print "\nFailed to update cargo packages."
    return 1
  fi

  _update_timestamps "cargo_last_update"
}

function up() {
  local update_task_count=${#UPDATE_TASKS[@]}

  for (( i=1; i<=update_task_count; i++ )); do
    local task="${UPDATE_TASKS[i]}"
    local parts=("${(@s:|:)task}")
    local command="${parts[4]}"

    if ! ${command}; then
      return 1
    fi

    if (( i < update_task_count )); then
      print
    fi
  done
}
