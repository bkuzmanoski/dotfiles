#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Sample Color
# @raycast.packageName System
# @raycast.icon icons/sample-color.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Output format", "data": [{"title": "Hexadecimal", "value": "--hex"}, {"title": "RGB", "value": "--rgb"}] }
# @raycast.mode silent

${0:A:h}/helpers/run_command.sh SampleColor "$@"
