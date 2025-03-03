UPDATE_TIMESTAMPS_DIR="${HOME}/.update_timestamps"
UPDATE_CHECKS=(
  # Format: [emoji]:[description]:[timestamp_file]:[update_command]
  "🍺:brew:${UPDATE_TIMESTAMPS_DIR}/brew_last_update:brewup"
  "📦:fnm:${UPDATE_TIMESTAMPS_DIR}/fnm_last_update:fnmup"
  "🔍:fzf-tab:${UPDATE_TIMESTAMPS_DIR}/fzf_tab_last_update:ftup"
  "🤖:GitHub Copilot:${UPDATE_TIMESTAMPS_DIR}/gh_copilot_last_update:gh extension upgrade gh-copilot"
)

# Install plugins
FZF_TAB_DIR="${HOME}/.zsh/fzf-tab"

if [[ ! -d "${FZF_TAB_DIR}" ]]; then
  print "Installing fzf-tab..."
  git clone https://github.com/Aloxaf/fzf-tab "${FZF_TAB_DIR}" || { print "fzf-tab installation failed.\n"; exit 1; }
  date +%s > "${UPDATE_TIMESTAMPS_DIR}/fzf_tab_last_update"
  print
fi

gh_copilot=$(gh extension list | grep "copilot")
if [[ -z "${gh_copilot}" ]]; then
  print "Installing GitHub Copilot..."
  gh extension install github/gh-copilot || { print "GitHub Copilot installation failed.\n"; exit 1; }
  gh copilot alias -- zsh | sed -e 's/ghce()/ce()/g' -e 's/ghcs()/cs()/g' > ${HOME}/.zsh/gh_copilot.zsh
  date +%s > "${UPDATE_TIMESTAMPS_DIR}/gh_copilot_last_update"
  print
fi

# Update reminders
check_update_timestamps() {
  local now="$(date +%s)"
  local thirty_days=$((30 * 86400)) # 30 days in seconds
  local updates_required=0

  [[ ! -d "${UPDATE_TIMESTAMPS_DIR}" ]] && mkdir -p "${UPDATE_TIMESTAMPS_DIR}" >&/dev/null

  for check in "${UPDATE_CHECKS[@]}"; do
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

  date +%s > "${UPDATE_TIMESTAMPS_DIR}/brew_last_update"
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

  date +%s > "${UPDATE_TIMESTAMPS_DIR}/fnm_last_update"
  print "fnm update timestamp updated, next reminder in 30 days."
}

ftup() (
  (cd "${FZF_TAB_DIR}" && git pull) || { print "fzf-tab update failed."; exit 1; }

  date +%s > "${UPDATE_TIMESTAMPS_DIR}/fzf_tab_last_update"
  print "fzf-tab update timestamp updated, next reminder in 30 days."
)
