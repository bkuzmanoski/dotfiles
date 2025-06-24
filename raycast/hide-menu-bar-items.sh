#!/bin/zsh

# @raycast.title Hide Menu Bar Items
# @raycast.packageName Utilities
# @raycast.icon icons/hide-menu-bar-items.png

# @raycast.argument1 { "type": "dropdown", "placeholder": "Command", "data": [{"title": "Toggle", "value": "toggle"}, {"title": "Quit", "value": "quit"}] }
# @raycast.mode silent

# @raycast.schemaVersion 1

${HOME}/.dotfiles/utils/run_command.sh HideMenuBarItems --background "$@"