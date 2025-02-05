#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
  color="${DEFAULT_DARK}"
else
  color="${DEFAULT_LIGHT}"
fi

case "${SENDER}" in
  "appearance_changed")
    sketchybar --set "${NAME}" label.color="${color}"
    ;;
  *)
    case "${NAME}" in
      "date") sketchybar --set "${NAME}" label="$(date '+%a %-d %b')" label.color="${color}"
      ;;
      "time") sketchybar --set "${NAME}" label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${color}"
      ;;
    esac
    ;;
esac
