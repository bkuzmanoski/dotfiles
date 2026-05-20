#!/bin/zsh

# @raycast.title Measure Pixels
# @raycast.packageName Utilities
# @raycast.icon icons/measure-pixels.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Mode", "data": [{"title": "Single", "value": "--single"}, {"title": "Continuous", "value": "--continuous"}] }
# @raycast.mode silent
# @raycast.schemaVersion 1

${HOME}/.dotfiles/utils/run_util.sh MeasurePixels "$1"
