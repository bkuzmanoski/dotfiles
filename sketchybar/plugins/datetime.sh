#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

if [[ "${SENDER}" == "appearance_change" ]]; then
  sketchybar \
    --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
    --set date label.color="${TEXT_DEFAULT_COLOR}" \
    --set time label.color="${TEXT_DEFAULT_COLOR}" update_freq=${UPDATE_FREQUENCY}
else
  sketchybar \
    --set date label="$(date '+%a %-d %b')" label.color="${TEXT_DEFAULT_COLOR}" \
    --set time label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${TEXT_DEFAULT_COLOR}" update_freq=${UPDATE_FREQUENCY}
fi
