#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Sample Color
# @raycast.mode silent
# @raycast.packageName System
# @raycast.icon icons/sample-color.png

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/helpers/run_command.zsh"
run_command SampleColor
