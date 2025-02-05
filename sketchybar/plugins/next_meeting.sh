#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
  color="${DEFAULT_DARK}"
else
  color="${DEFAULT_LIGHT}"
fi

case "${SENDER}" in
  "appearance_changed")
    sketchybar --set "${NAME}" label.color="${color}"
    ;;
  *)
    next_meeting="$("${CONFIG_DIR}/helpers/GetNextMeeting.swift")"
    sketchybar --set "${NAME}" label="${next_meeting}" label.color="${color}"
    ;;
esac
