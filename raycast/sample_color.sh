#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Sample Color
# @raycast.mode silent
#
# Optional parameters:
# @raycast.packageName System
#
# Documentation:
# @raycast.author Brian Kuzmanoski
# @raycast.authorURL https://github.com/bkuzmanoski

SCRIPT_DIR="${0:A:h}"

"${SCRIPT_DIR}/helpers/run_command.sh" SampleColor
