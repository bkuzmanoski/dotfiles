#!/bin/zsh

case "${NAME}" in
  "current_app_icon")
    if [[ -z "${INFO}" ]]; then
      # Sketchybar sends unset INFO variable if --update is triggered manually (e.g. on startup)
      # This hides the app icon until the next application focus event so we can use the app name to get an icon
      sketchybar --set "${NAME}" drawing=off
    else
      icon_path="${HOME}/.cache/sketchybar/app-icons/${INFO}.png"
      scale=0.5

      # Check if app icon is already cached
      if [[ ! -f "${icon_path}" ]]; then
          # Replace built-in Sketchybar "app.<name>" functionality for higher quality scaling
          "${CONFIG_DIR}/helpers/getAppIcon.swift" "${INFO}" > /dev/null

          if (( $? != 0 )); then
              # Fallback to Sketchybar to get app icon on error
              icon_path="app.${INFO}"
              scale=0.6923076923 # ~18x18px
          fi
      fi

      sketchybar --set "${NAME}" drawing=on background.image="${icon_path}" background.image.scale=${scale}
    fi
  ;;
  "current_app_name")
    source "${CONFIG_DIR}/colors.sh"

    if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
      label_color="${LABEL_DARK}"
    else
      label_color="${LABEL_LIGHT}"
    fi

    case "${SENDER}" in
      "appearance_changed") sketchybar --set "${NAME}" label.color="${label_color}" ;;
      "front_app_switched") sketchybar --set "${NAME}" label="${INFO}" label.color="${label_color}" ;;
    esac
  ;;
esac
