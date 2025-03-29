#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  mouse.entered)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set app_icon background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  mouse.exited)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set app_icon background.color=0x00ffffff
    ;;
  mouse.clicked)
    if [[ "${BUTTON}" != "left" ]]; then return; fi

    sketchybar --set app_icon background.color="${BACKGROUND_ACTIVE_COLOR}"
    open -g "hammerspoon://showAppMenu?x=8&y=45"
    sleep $(print "scale=2; ${ANIMATION_DURATION} / 100" | bc)
    sketchybar --set app_icon background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
esac
