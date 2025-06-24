#!/bin/zsh

# @raycast.title Sample Color
# @raycast.packageName Utilities
# @raycast.icon icons/sample-color.png

# @raycast.argument1 { "type": "dropdown", "placeholder": "Output format", "data": [{"title": "Hexadecimal", "value": "--hex"}, {"title": "RGB", "value": "--rgb"}] }
# @raycast.mode silent

# @raycast.schemaVersion 1

${HOME}/.dotfiles/utils/run_command.sh SampleColor "$@"
