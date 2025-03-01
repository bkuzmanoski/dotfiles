#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

seconds_to_next_minute=$((60 - $(date '+%-S')))

if [[ "${SENDER}" == "appearance_change" ]]; then
  sketchybar \
    --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
    --set date label.color="${FOREGROUND_COLOR}" \
    --set time label.color="${FOREGROUND_COLOR}" update_freq=${seconds_to_next_minute}
else
  sketchybar \
    --set date label="$(date '+%a %-d %b')" label.color="${FOREGROUND_COLOR}" \
    --set time label="$(date '+%-I:%M %p' | tr '[:upper:]' '[:lower:]')" label.color="${FOREGROUND_COLOR}" update_freq=${seconds_to_next_minute}
fi

# Update the next event and battery status
if [[ "${SENDER}" != "appearance_change" ]]; then
  export SENDER="time_change"
fi

"${CONFIG_DIR}/plugins/next_event.sh" # Get accruate countdown to next event
"${CONFIG_DIR}/plugins/battery_status.sh" # Battery level change notifications are sent at most once per minute anyway
