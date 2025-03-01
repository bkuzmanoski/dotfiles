#!/bin/zsh

source "${CONFIG_DIR}/variables.sh"

if [[ "${SENDER}" == "appearance_change" ]]; then
  sketchybar \
    --animate ${ANIMATION_CURVE} ${ANIMATION_DURATION} \
    --set battery_status icon.color="${FOREGROUND_WARNING_COLOR}" label.color="${FOREGROUND_WARNING_COLOR}"
else
  battery_info="$(pmset -g batt)"
  is_discharging="$(print "${battery_info}" | grep "discharging")"
  percentage="$(print "${battery_info}" | grep -Eo "\d+%" | cut -d% -f1)"

  if [[ -n "${is_discharging}" && "${percentage}" =~ ^[0-9]+$ && "${percentage}" -le 20 ]]; then
    sketchybar --set battery_status drawing=on icon.color="${FOREGROUND_WARNING_COLOR}" label="${percentage}%" label.color="${FOREGROUND_WARNING_COLOR}"
  else
    sketchybar --set battery_status drawing=off
  fi
fi
