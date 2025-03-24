#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  appearance_change)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set next_event label.color="${TEXT_INVERSE_COLOR}" background.color="${BACKGROUND_DEFAULT_COLOR}"
    ;;
  calendar_updated)
    local next_event="$("${CONFIG_DIR}/helpers/bin/GetNextEvent")"
    if [[ $? -ne 0 ]] || [[ -z "${next_event}" ]]; then
      sketchybar --set next_event drawing=off
    else
      sketchybar --set next_event drawing=on label="${next_event}" label.color="${TEXT_INVERSE_COLOR}" background.color="${BACKGROUND_DEFAULT_COLOR}" update_freq="${UPDATE_FREQUENCY}"
    fi
    ;;
  mouse.entered)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set next_event background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  mouse.exited)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set next_event background.color="${BACKGROUND_DEFAULT_COLOR}"
    ;;
  mouse.clicked)
    sketchybar --set next_event background.color="${BACKGROUND_ACTIVE_COLOR}"
    sleep $(print "scale=2; ${ANIMATION_DURATION} / 100" | bc)
    sketchybar --set next_event background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
esac
