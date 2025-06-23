#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Scroll to Zoom
# @raycast.packageName System
# @raycast.icon icons/scroll-to-zoom.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Command", "data": [{"title": "Launch", "value": "launch"}, {"title": "Quit", "value": "quit"}] }
# @raycast.mode silent

nohup ${0:A:h}/helpers/run_command.sh ScrollToZoom "${@}" &
