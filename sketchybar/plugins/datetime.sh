#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
  label_color="${LABEL_DARK}"
else
  label_color="${LABEL_LIGHT}"
fi

sketchybar --set date label="$(date '+%a %-d %b')" label.color="${label_color}"
sketchybar --set time label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${label_color}"
