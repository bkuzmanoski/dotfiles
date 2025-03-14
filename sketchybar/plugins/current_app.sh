#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  appearance_change)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set current_app_name label.color="${TEXT_DEFAULT_COLOR}"
    ;;
  app_change)
    icon_path="${HOME}/.cache/sketchybar/icons/${BUNDLE_ID}.png"
    arguments=(--set current_app_name label="${APP_NAME}" label.color="${TEXT_DEFAULT_COLOR}")
    return_value=0
    if [[ ! -f "${icon_path}" ]]; then
      "${CONFIG_DIR}/helpers/bin/GetAppIcon" "${BUNDLE_ID}" >/dev/null
      return_value="$?"
    fi

    if [[ ${return_value} -eq 0 ]]; then
      arguments+=(--set current_app_icon drawing=on background.image="${icon_path}")
    else
      arguments+=(--set current_app_icon drawing=off)
    fi

    sketchybar "${arguments[@]}"
    ;;
esac
