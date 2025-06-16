#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Send Active Tab to Feedbin
# @raycast.packageName Google Chrome
# @raycast.icon icons/send-tabs-to-feedbin.png
# @raycast.mode silent

${0:A:h}/helpers/run_command.sh SendTabsToFeedbin --active-only
