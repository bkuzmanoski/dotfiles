#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

case "${SENDER}" in
  "appearance_change")
    sketchybar --set "${NAME}" icon.color="${ICON_WARNING_COLOR}" label.color="${LABEL_WARNING_COLOR}"
    ;;
  *)
    battery_info="$(pmset -g batt)"

    is_discharging="$(print "${battery_info}" | grep "discharging")"
    percentage="$(print "${battery_info}" | grep -Eo "\d+%" | cut -d% -f1)"

    if [[ -n "${is_discharging}" && "${percentage}" =~ ^[0-9]+$ && "${percentage}" -le 10 ]]; then
      sketchybar --set "${NAME}" drawing=on label="${percentage}%" icon.color="${ICON_WARNING_COLOR}" label.color="${LABEL_WARNING_COLOR}"
    else
      sketchybar --set "${NAME}" drawing=off
    fi
    ;;
esac
