#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Menu Bar Item Hider
# @raycast.packageName System
# @raycast.icon icons/menubar-item-hider.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Command", "data": [{"title": "Toggle", "value": "toggle"}, {"title": "Quit", "value": "quit"}] }
# @raycast.mode silent

nohup ${0:A:h}/helpers/run_command.sh MenuBarItemHider "${@}" &
