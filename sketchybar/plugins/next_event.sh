#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  "appearance_change")
    sketchybar \
      --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
      --set ${NAME} label.color="${FOREGROUND_COLOR}" background.color="${BACKGROUND_COLOR}"
    ;;
  "mouse.entered")
    sketchybar --set ${NAME} background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  "mouse.exited")
    sketchybar --set ${NAME} background.color="${BACKGROUND_COLOR}"
    ;;
  "mouse.clicked")
    sketchybar --set ${NAME} background.color="${BACKGROUND_ACTIVE_COLOR}"
    sleep 0.1
    sketchybar --set ${NAME} background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  *)
    next_event="$("${CONFIG_DIR}/helpers/GetNextEvent.swift")"

    if [[ $? -ne 0 ]] || [[ -z "${next_event}" ]]; then
      sketchybar --set ${NAME} drawing=off
    else
      sketchybar --set ${NAME} drawing=on label="${next_event}" label.color="${FOREGROUND_COLOR}" background.color="${BACKGROUND_COLOR}"
    fi
    ;;
esac
