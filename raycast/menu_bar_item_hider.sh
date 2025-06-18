#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Menu Bar Item Hider
# @raycast.packageName System
# @raycast.icon icons/menu-bar-item-hider.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Action", "data": [{"title": "Toggle", "value": "--toggle"}, {"title": "Quit", "value": "--quit"}] }
# @raycast.mode silent

${0:A:h}/helpers/run_command.sh MenuBarItemHider "$@"
