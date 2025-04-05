#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  mouse.entered)
    sketchybar --set app_icon background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  mouse.exited)
    sketchybar --set app_icon background.color=0x00000000
    ;;
  mouse.clicked)
    if [[ "${BUTTON}" != "left" ]]; then return; fi

    sketchybar --set app_icon background.color="${BACKGROUND_ACTIVE_COLOR}"
    open -g "hammerspoon://showAppMenu?x=8&y=45" &
    sleep $(awk "BEGIN {print ${THEME_ANIMATION_DURATION} / 100}")
    sketchybar --set app_icon background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
esac
