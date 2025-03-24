#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  appearance_changed)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set date_time icon.color="${TEXT_DEFAULT_COLOR}" label.color="${TEXT_DEFAULT_COLOR}" update_freq="${UPDATE_FREQUENCY}"
    ;;
  *)
    sketchybar \
      --set date_time \
        icon="$(date "+%a %-d %b")" icon.color="${TEXT_DEFAULT_COLOR}" \
        label="$(date "+%-I:%M %p" | tr '[:upper:]' '[:lower:]')" label.color="${TEXT_DEFAULT_COLOR}" \
        update_freq="${UPDATE_FREQUENCY}"
    ;;
esac
