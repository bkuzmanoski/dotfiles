#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

label_color=${TEXT_DEFAULT_COLOR}
background_color=0x00000000

if [[ $(sketchybar --query next_event | jq -r ".label?.value // empty") == *now ]]; then
  label_color=${TEXT_INVERSE_COLOR}
  background_color=${BACKGROUND_WARNING_COLOR}
fi

case "${SENDER}" in
  appearance_changed)
    sketchybar \
      --animate "${ANIMATION_CURVE}" "${ANIMATION_DURATION}" \
      --set next_event icon.color="${label_color}" label.color="${label_color}" background.color="${background_color}"
    ;;
  mouse.entered)
    sketchybar --set next_event icon.color="${TEXT_DEFAULT_COLOR}" label.color="${TEXT_DEFAULT_COLOR}" background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  mouse.exited)
    sketchybar --set next_event icon.color="${label_color}" label.color="${label_color}" background.color="${background_color}"
    ;;
  mouse.clicked)
    if [[ "${BUTTON}" != "left" ]]; then return; fi

    sketchybar --set next_event background.color="${BACKGROUND_ACTIVE_COLOR}"
    ${CONFIG_DIR}/helpers/bin/GetNextEvent --open-url &
    sleep $(awk "BEGIN {print ${ANIMATION_DURATION} / 100}")
    sketchybar --set next_event background.color="${BACKGROUND_HOVER_COLOR}"
    ;;
  *)
    next_event="$("${CONFIG_DIR}/helpers/bin/GetNextEvent")"
    if [[ $? -ne 0 ]] || [[ -z "${next_event}" ]]; then
      sketchybar --set next_event drawing=off
    else
      if [[ ${next_event} == *now ]]; then
        label_color=${TEXT_INVERSE_COLOR}
        background_color=${BACKGROUND_WARNING_COLOR}
      fi

      sketchybar --set next_event drawing=on label="${next_event}" icon.color="${label_color}" label.color="${label_color}" background.color="${background_color}" update_freq="${UPDATE_FREQUENCY}"
    fi
    ;;
esac
