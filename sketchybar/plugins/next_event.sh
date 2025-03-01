#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

update_item() {
  local  next_event="$("${CONFIG_DIR}/helpers/bin/GetNextEvent")"

  if [[ $? -ne 0 ]] || [[ -z "${next_event}" ]]; then
    sketchybar --set next_event drawing=off
  else
    sketchybar --set next_event drawing=on label="${next_event}" label.color="${FOREGROUND_COLOR}" background.color="${BACKGROUND_COLOR}"
  fi
}

case "${SENDER}" in
  "appearance_change")
    sketchybar \
      --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
      --set next_event label.color="${FOREGROUND_COLOR}" background.color="${BACKGROUND_COLOR}"
    ;;
  "mouse.entered")
    sketchybar --set next_event background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  "mouse.exited")
    sketchybar --set next_event background.color="${BACKGROUND_COLOR}"
    ;;
  "mouse.clicked")
    sketchybar --set next_event background.color="${BACKGROUND_ACTIVE_COLOR}"
    sleep 0.1
    sketchybar --set next_event background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  "time_change")
    if [[ "$(sketchybar --query next_event | jq -r ".geometry.drawing")" == "on" ]]; then
      update_item
    fi
    ;;
  *)
    update_item
    ;;
esac
