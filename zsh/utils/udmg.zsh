function udmg() {
  function print_usage() {
    command cat <<-"EOF"
			Usage:
			  udmg [options]

			Options:
			  -f, --force    Force detach (unmount) even if the disk is busy
			  -h, --help     Show this help message
		EOF
  }

  if ! zparseopts -D -E -F \
    {f,-force}=flag_force \
    {h,-help}=flag_help \
    2>/dev/null; then
    print -u2 "Error: Invalid option(s).\n"
    print_usage >&2

    return 1
  fi

  if (($# > 0)); then
    print -u2 "Error: Unexpected argument: $1\n"
    print_usage >&2

    return 1
  fi

  if ((${#flag_help} > 0)); then
    print_usage
    return 0
  fi

  local raw_output="$(hdiutil info -plist | plutil -convert json -o - - | jq -r '.images[]? | select(."system-entities" != null and (."system-entities" | length) > 0) | "\(.["system-entities"][0]["dev-entry"])\t\(.["image-path"])"' 2>/dev/null)"

  if [[ -z "${raw_output}" ]]; then
    print "No mounted DMG images found."
    return 0
  fi

  local -a mounted_dmgs=(${(f)raw_output})

  local dmg
  local device
  local dmg_path
  local -i fail_count=0

  for ((i = 1; i <= ${#mounted_dmgs[@]}; i++)); do
    device="${mounted_dmgs[i]%$'\t'*}"
    dmg_path="${mounted_dmgs[i]#*$'\t'}"

    if [[ -z "${device}" ]]; then
      continue
    fi

    local -a detach_cmd=(hdiutil detach "${device}")

    if ((${#flag_force} > 0)); then
      detach_cmd+=(-force)
    fi

    print -P "Detaching %B${device}%b (${dmg_path:t})..."

    if ! "${detach_cmd[@]}"; then
      print -u2 -P "%F{1}Error:%f Failed to detach ${dmg_path}"
      ((fail_count++))
    fi

    if ((i < ${#mounted_dmgs[@]})); then
      print
    fi
  done

  if ((fail_count > 0)); then
    return 1
  fi
}
