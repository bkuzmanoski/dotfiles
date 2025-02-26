#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  "appearance_change")
    sketchybar \
      --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
      --set current_app_name label.color="${FOREGROUND_COLOR}"
    ;;
  "window_change")
    arguments=()

    if [[ "${BUNDLE_ID}" ]]; then
      icon_path="${HOME}/.cache/sketchybar/app-icons/${BUNDLE_ID}.png"
      scale=0.5 # 2x retina resolution
      return_value=0

      if [[ ! -f "${icon_path}" ]]; then
        "${CONFIG_DIR}/helpers/GetAppIcon.swift" "${BUNDLE_ID}" > /dev/null
        return_value=$?
      fi

      if [[ return_value -eq 0 ]]; then
        arguments+=(--set current_app_icon drawing=on background.image="${icon_path}" background.image.scale=${scale})
      else
        arguments+=(--set current_app_icon drawing=off)
      fi
    fi

    arguments+=(--set current_app_name label="${TITLE}" label.color="${FOREGROUND_COLOR}")

    sketchybar "${arguments[@]}"
    ;;
esac
