#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Show Desktops
# @raycast.mode silent
# @raycast.packageName Window Management
# @raycast.author Brian Kuzmanoski
# @raycast.authorURL https://github.com/bkuzmanoski

SCRIPT_DIR="${0:A:h}"
source "${SCRIPT_DIR}/helpers/run_command.zsh"
run_command ShowDesktops
