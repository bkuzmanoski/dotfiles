#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
  label_color="${LABEL_DARK}"
else
  label_color="${LABEL_LIGHT}"
fi

case "${SENDER}" in
  "appearance_changed")
    sketchybar --set "${NAME}" label.color="${label_color}"
    ;;
  *)
    case "${NAME}" in
      "date") sketchybar --set "${NAME}" label="$(date '+%a %-d %b')" label.color="${label_color}"
      ;;
      "time") sketchybar --set "${NAME}" label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${label_color}"
      ;;
    esac
    ;;
esac
