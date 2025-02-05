#!/bin/zsh

source "${CONFIG_DIR}/colors.sh"

if [[ $(defaults read NSGlobalDomain AppleInterfaceStyle 2> /dev/null) == "Dark" ]]; then
  color="${WARNING_DARK}"
else
  color="${WARNING_LIGHT}"
fi

case "${SENDER}" in
  "appearance_changed")
    sketchybar --set "${NAME}" icon.color="${color}" label.color="${color}"
    ;;
  *)
    battery_info="$(pmset -g batt)"

    is_discharging="$(print "${battery_info}" | grep "discharging")"
    percentage="$(print "${battery_info}" | grep -Eo "\d+%" | cut -d% -f1)"
    time_remaining="$(print "${battery_info}" | grep -Eo "\d+:\d+" | head -n1)"

    if [[ -n "${is_discharging}" && "${percentage}" =~ ^[0-9]+$ && "${percentage}" -le 10 ]]; then
      message="Low battery"

      if [[ -n "${time_remaining}" ]]; then
        hours=${time_remaining%:*}
        minutes=${time_remaining#*:}
        total_minutes=$((10#${hours} * 60 + 10#${minutes}))

        if ((total_minutes >= 60)); then
            display_hours=$((total_minutes / 60))
            display_minutes=$((total_minutes % 60))
            message+=" (${display_hours}h ${display_minutes}m left)"
        else
            message+=" (${total_minutes}m left)"
        fi
      fi

      sketchybar --set "${NAME}" drawing=on icon.color="${color}" label.color="${color}" label="${message}"
    else
     sketchybar --set "${NAME}" drawing=off
    fi
    ;;
esac
