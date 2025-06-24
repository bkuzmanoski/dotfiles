#!/bin/zsh

# @raycast.title Scroll to Zoom
# @raycast.packageName Utilities
# @raycast.icon icons/scroll-to-zoom.png

# @raycast.argument1 { "type": "dropdown", "placeholder": "Command", "data": [{"title": "Launch", "value": "launch"}, {"title": "Quit", "value": "quit"}] }
# @raycast.mode silent

# @raycast.schemaVersion 1

${HOME}/.dotfiles/utils/run_command.sh ScrollToZoom --background "$@"
