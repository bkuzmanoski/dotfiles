#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

case "${SENDER}" in
  appearance_changed)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set app_name label.color="${TEXT_DEFAULT_COLOR}"
    ;;
  mouse.entered)
    app_name="$(sketchybar --query app_name | jq -r ".label?.value // empty") 􀄥"
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set window_title padding_left=8 label.color=0x00000000
    sketchybar --set app_name label="${app_name}" background.color="${BACKGROUND_HOVER_COLOR}"

    ;;
  mouse.exited)
    sketchybar \
      --set app_name background.color=0x00000000 \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set window_title label.color="${TEXT_DEFAULT_COLOR}" padding_left=0
    ;;
  mouse.clicked)
    if [[ "${BUTTON}" != "left" ]]; then return; fi

    sketchybar --set app_name background.color="${BACKGROUND_ACTIVE_COLOR}"
    open -g "hammerspoon://showAppMenu?x=13&y=41" &
    sleep $(awk "BEGIN {print ${ANIMATION_DURATION} / 100}")
    sketchybar --set app_name background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  app_activated)
    arguments=()
    icon_path="${HOME}/.cache/sketchybar/icons/${BUNDLE_ID}.png"
    return_value=0

    if [[ ! -f "${icon_path}" ]]; then
      "${CONFIG_DIR}/helpers/bin/GetAppIcon" "${BUNDLE_ID}" >/dev/null
      return_value="$?"
    fi

    if [[ ${return_value} -eq 0 ]]; then
      arguments+=(--set app_name icon.drawing=on icon.background.image="${icon_path}")
    else
      arguments+=(--set app_name icon.drawing=off)
    fi

    arguments+=(--set app_name label="${APP_NAME}" label.color="${TEXT_DEFAULT_COLOR}")
    arguments+=(--set window_title label="${WINDOW_TITLE}" label.color="${TEXT_DEFAULT_COLOR}")

    sketchybar "${arguments[@]}"
    ;;
esac
