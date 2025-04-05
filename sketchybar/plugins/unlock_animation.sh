#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  screen_locked)
    sleep 0.2 # Wait for screen to fade out before bar disappears
    sketchybar --bar y_offset=-40 margin=-160
  ;;
  screen_unlocked)
    sleep 0.2 # Wait for system to stabilize to avoid glitches
    afplay "${CONFIG_DIR}/assets/unlock.wav" &
    sketchybar \
      --animate "${ANIMATION_CURVE}" $((ANIMATION_DURATION * 2)) \
      --bar y_offset=0 margin=0
  ;;
esac
