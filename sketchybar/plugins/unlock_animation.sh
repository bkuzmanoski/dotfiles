#!/bin/zsh

case "${SENDER}" in
  screen_locked)
    sleep 0.2 # Wait for screen to fade out before bar disappears
    sketchybar --bar y_offset=-$(sketchybar --query bar | jq '.height')
  ;;
  screen_unlocked)
    sleep 0.2 # Wait for system to stabilize to avoid glitches
    source "${CONFIG_DIR}/variables.sh"
    [[ ${UNLOCK_SOUND} -eq 1 ]] && afplay "${CONFIG_DIR}/assets/unlock.wav" &
    sketchybar \
      --animate "${UNLOCK_ANIMATION_CURVE}" ${UNLOCK_ANIMATION_DURATION} \
      --bar y_offset=0
  ;;
esac
