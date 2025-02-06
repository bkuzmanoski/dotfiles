#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
  icon_color="${ICON_DARK}"
  label_color="${LABEL_DARK}"
  background_color="${BACKGROUND_DARK}"
  background_hover_color="${BACKGROUND_HOVER_DARK}"
  background_active_color="${BACKGROUND_ACTIVE_DARK}"
  border_color="${BORDER_DARK}"
else
  icon_color="${ICON_LIGHT}"
  label_color="${LABEL_LIGHT}"
  background_color="${BACKGROUND_LIGHT}"
  background_hover_color="${BACKGROUND_HOVER_LIGHT}"
  background_active_color="${BACKGROUND_ACTIVE_LIGHT}"
  border_color="${BORDER_LIGHT}"
fi

case "${SENDER}" in
  "appearance_changed")
    sketchybar --set "${NAME}" icon.color="${icon_color}" label.color="${label_color}" background.color="${background_color}" background.border_color="${border_color}"
    ;;
  "mouse.entered")
    sketchybar --set "${NAME}" background.color="${background_hover_color}"
    ;;
  "mouse.exited")
    sketchybar --set "${NAME}" background.color="${background_color}"
    ;;
  "mouse.clicked")
    sketchybar --set "${NAME}" background.color="${background_active_color}"
    sleep 0.1
    sketchybar --set "${NAME}" background.color="${background_hover_color}"
    ;;
  *)
    next_meeting="$("${CONFIG_DIR}/helpers/getNextMeeting.swift")"

    if [[ -z "${next_meeting}" ]]; then
      sketchybar --set "${NAME}" drawing=off
    else
      sketchybar --set "${NAME}" drawing=on label="${next_meeting}" icon.color="${icon_color}" label.color="${label_color}" background.color="${background_color}" background.border_color="${border_color}"
    fi
    ;;
esac
