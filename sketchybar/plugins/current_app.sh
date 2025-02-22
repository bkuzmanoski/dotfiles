#!/bin/zsh

case "${NAME}" in
  "current_app_icon")
    [[ ! "${BUNDLE_ID}" ]] && exit 0

    icon_path="${HOME}/.cache/sketchybar/app-icons/${BUNDLE_ID}.png"
    scale=0.5

    # Check if app icon is already cached
    if [[ ! -f "${icon_path}" ]]; then
        # Replace built-in Sketchybar "app.<name>" functionality for higher quality scaling
        "${CONFIG_DIR}/helpers/GetAppIcon.swift" "${BUNDLE_ID}" > /dev/null

        if [[ $? -ne 0 ]]; then
            # Fallback to Sketchybar to get app icon on error
            icon_path="app.${INFO}"
            scale=0.6923076923 # ~18x18px
        fi
    fi

    sketchybar --set "${NAME}" drawing=on background.image="${icon_path}" background.image.scale=${scale}
    ;;
  "current_app_name")
    source "${CONFIG_DIR}/colors.sh"

    case "${SENDER}" in
      "appearance_change")
        sketchybar --set "${NAME}" label.color="${LABEL_COLOR}"
        ;;
      "window_change")
        sketchybar --set "${NAME}" label="${TITLE}" label.color="${LABEL_COLOR}"
        ;;
    esac
    ;;
esac
