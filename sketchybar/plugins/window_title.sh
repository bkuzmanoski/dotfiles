#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  appearance_changed)
    sketchybar \
      --animate "${THEME_ANIMATION_CURVE}" "${THEME_ANIMATION_DURATION}" \
      --set window_title label.color="${TEXT_DEFAULT_COLOR}"
    ;;
  window_title_changed)
    sketchybar --set window_title label="${WINDOW_TITLE}" label.color="${TEXT_DEFAULT_COLOR}"
    ;;
esac
