#!/bin/zsh

# @raycast.title Sample Color
# @raycast.packageName Utilities
# @raycast.icon icons/sample-color.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Output format", "data": [{"title": "Hexadecimal", "value": "hex"}, {"title": "RGB", "value": "rgb"}] }
# @raycast.argument2 { "type": "dropdown", "placeholder": "Color space", "data": [{"title": "sRGB", "value": "srgb"}, {"title": "Native", "value": "native"}] }
# @raycast.mode silent
# @raycast.schemaVersion 1

# Raycast times out scripts after 30 seconds.
${HOME}/.dotfiles/utils/run_util.sh --detach-after 27 SampleColor --format "$1" --color-space "$2"
