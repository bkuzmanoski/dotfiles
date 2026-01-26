#!/bin/zsh

# @raycast.title Send Active Chrome Tab to Feedbin
# @raycast.packageName Utilities
# @raycast.icon icons/send-chrome-tabs-to-feedbin.png
# @raycast.mode silent
# @raycast.schemaVersion 1

${HOME}/.dotfiles/utils/run_command.sh SendChromeTabs "bwilw@feedb.in" --active-only --close-sent
