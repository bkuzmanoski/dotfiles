#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  "appearance_change")
    sketchybar \
      --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
      --set next_event label.color="${FOREGROUND_COLOR}" background.color="${BACKGROUND_COLOR}"
    ;;
  "mouse.entered")
    sketchybar \
      --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
      --set next_event background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  "mouse.exited")
    sketchybar \
      --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
      --set next_event background.color="${BACKGROUND_COLOR}"
    ;;
  "mouse.clicked")
    sketchybar --set next_event background.color="${BACKGROUND_ACTIVE_COLOR}"
    sleep 0.1
    sketchybar --set next_event background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  *)
    local  next_event="$("${CONFIG_DIR}/helpers/bin/GetNextEvent")"

    if [[ $? -ne 0 ]] || [[ -z "${next_event}" ]]; then
      sketchybar --set next_event drawing=off
    else
      sketchybar --set next_event drawing=on label="${next_event}" label.color="${FOREGROUND_COLOR}" background.color="${BACKGROUND_COLOR}" update_freq=${UPDATE_FREQUENCY}
    fi
    ;;
esac
