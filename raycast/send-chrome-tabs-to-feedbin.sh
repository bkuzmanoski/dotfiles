#!/bin/zsh

# @raycast.title Send Chrome Tabs to Feedbin
# @raycast.packageName Utilities
# @raycast.icon icons/send-chrome-tabs-to-feedbin.png
# @raycast.argument1 { "type": "dropdown", "placeholder": "Tabs", "data": [{"title": "Current Tab", "value": "--active-only"}, {"title": "All Tabs", "value": ""}] }
# @raycast.argument2 { "type": "dropdown", "placeholder": "After Sending", "data": [{"title": "Close Tab(s)", "value": "--close-sent"}, {"title": "Keep Tab(s) Open", "value": ""}] }
# @raycast.mode silent
# @raycast.schemaVersion 1

${HOME}/.dotfiles/utils/run_util.sh SendChromeTabs "bwilw@feedb.in" "$1" "$2"
