#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
  icon_color="${WARNING_ICON_DARK}"
  label_color="${WARNING_LABEL_DARK}"
else
  icon_color="${WARNING_ICON_LIGHT}"
  label_color="${WARNING_LABEL_LIGHT}"
fi

case "${SENDER}" in
  "appearance_change")
    sketchybar --set "${NAME}" icon.color="${icon_color}" label.color="${label_color}"
    ;;
  *)
    battery_info="$(pmset -g batt)"

    is_discharging="$(print "${battery_info}" | grep "discharging")"
    percentage="$(print "${battery_info}" | grep -Eo "\d+%" | cut -d% -f1)"

    if [[ -n "${is_discharging}" && "${percentage}" =~ ^[0-9]+$ && "${percentage}" -le 10 ]]; then
      sketchybar --set "${NAME}" drawing=on label="${percentage}%" icon.color="${icon_color}" label.color="${label_color}"
    else
      sketchybar --set "${NAME}" drawing=off
    fi
    ;;
esac
