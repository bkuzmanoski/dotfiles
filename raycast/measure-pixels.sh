#!/bin/zsh

# @raycast.title Measure Pixels
# @raycast.packageName Utilities
# @raycast.icon icons/measure.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title": "Single", "value": "--single"}, {"title": "Continuous", "value": "--continuous"}] }
# @raycast.mode silent
# @raycast.schemaVersion 1

# Raycast times out scripts after 30 seconds.
${HOME}/.dotfiles/utils/run_util.sh --detach-after 27 MeasurePixels "$1"
