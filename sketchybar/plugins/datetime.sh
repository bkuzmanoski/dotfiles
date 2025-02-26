#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

if [[ "${SENDER}" == "appearance_change" ]]; then
  sketchybar \
    --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
    --set date label.color="${FOREGROUND_COLOR}" \
    --set time label.color="${FOREGROUND_COLOR}"
else
  sketchybar \
    --set date label="$(date '+%a %-d %b')" label.color="${FOREGROUND_COLOR}" \
    --set time label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${FOREGROUND_COLOR}"
fi