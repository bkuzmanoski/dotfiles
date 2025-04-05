#!/bin/zsh

case "${SENDER}" in
  screen_locked)
    sleep 0.2 # Wait for screen to fade out before bar disappears
    sketchybar --bar y_offset=-$(sketchybar --query bar | jq '.height')
  ;;
  screen_unlocked)
    sleep 0.2 # Wait for system to stabilize to avoid glitches
    afplay "${CONFIG_DIR}/assets/unlock.wav" &
    source "${CONFIG_DIR}/variables.sh"
    sketchybar \
      --animate "${ANIMATION_CURVE}" ${ANIMATION_DURATION} \
      --bar y_offset=0
  ;;
esac
