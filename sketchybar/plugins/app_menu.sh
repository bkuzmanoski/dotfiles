#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  mouse.entered)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set current_app_icon background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  mouse.exited)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set current_app_icon background.color=0x00ffffff
    ;;
  mouse.clicked)
    sketchybar --set current_app_icon background.color="${BACKGROUND_ACTIVE_COLOR}"
    sleep $(print "scale=2; ${ANIMATION_DURATION} / 100" | bc)
    sketchybar --set current_app_icon background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
esac
