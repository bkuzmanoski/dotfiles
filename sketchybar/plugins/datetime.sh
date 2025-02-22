#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

sketchybar --set date label="$(date '+%a %-d %b')" label.color="${LABEL_COLOR}"
sketchybar --set time label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${LABEL_COLOR}"
