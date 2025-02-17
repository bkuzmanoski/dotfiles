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
  "appearance_changed")
    sketchybar --set "${NAME}" icon.color="${icon_color}" label.color="${label_color}"
    ;;
  *)
    battery_info="$(pmset -g batt)"

    is_discharging="$(print "${battery_info}" | grep "discharging")"
    percentage="$(print "${battery_info}" | grep -Eo "\d+%" | cut -d% -f1)"
    time_remaining="$(print "${battery_info}" | grep -Eo "\d+:\d+" | head -n1)"

    if [[ -n "${is_discharging}" && "${percentage}" =~ ^[0-9]+$ && "${percentage}" -le 10 ]]; then
      if [[ -n "${time_remaining}" ]]; then
        hours=${time_remaining%:*}
        minutes=${time_remaining#*:}
        total_minutes=$((10#${hours} * 60 + 10#${minutes}))

        if ((total_minutes >= 60)); then
          display_hours=$((total_minutes / 60))
          display_minutes=$((total_minutes % 60))
          message="${display_hours}h ${display_minutes}m left"
        else
          message="${total_minutes}m left"
        fi
      else
        message="Low battery!"
      fi

      sketchybar --set "${NAME}" drawing=on label="${message}" icon.color="${icon_color}" label.color="${label_color}"
    else
      sketchybar --set "${NAME}" drawing=off
    fi
    ;;
esac
