#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

sketchybar \
  --set date label="$(date '+%a %-d %b')" label.color="${FOREGROUND_COLOR}" \
  --set time label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${FOREGROUND_COLOR}"
