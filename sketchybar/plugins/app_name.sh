#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  appearance_changed)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set app_name label.color="${TEXT_DEFAULT_COLOR}"
    ;;
  app_activated)
    arguments=(--set app_name label="${APP_NAME}" label.color="${TEXT_DEFAULT_COLOR}")
    arguments+=(--set window_title label="${WINDOW_TITLE}" label.color="${TEXT_DEFAULT_COLOR}")

    icon_path="${HOME}/.cache/sketchybar/icons/${BUNDLE_ID}.png"
    return_value=0
    if [[ ! -f "${icon_path}" ]]; then
      "${CONFIG_DIR}/helpers/bin/GetAppIcon" "${BUNDLE_ID}" >/dev/null
      return_value="$?"
    fi

    if [[ ${return_value} -eq 0 ]]; then
      arguments+=(--set app_icon drawing=on background.image="${icon_path}")
    else
      arguments+=(--set app_icon drawing=off)
    fi

    sketchybar "${arguments[@]}"
    ;;
esac
