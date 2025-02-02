#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Purge Desktop
# @raycast.mode silent

# Optional parameters:
# @raycast.packageName System

# Documentation:
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

# Get the Desktop folder path and ensure it exists
DESKTOP_DIR="${HOME}/Desktop"

if [[ ! -d "${DESKTOP_DIR}" ]]; then
  print "Desktop directory not found."
  exit 1
fi

# Check if there are any files/folders to move
if [[ -z "$(ls "${DESKTOP_DIR}")" ]]; then
  print "Desktop folder is already empty."
  exit 0
fi

# Move items to trash
osascript << EOD
  tell application "Finder"
    set desktopFolder to POSIX file "${DESKTOP_DIR}" as alias
    delete (every item of folder desktopFolder)
  end tell
EOD

if (( ! $? )); then
  print "Successfully moved items to trash."
else
  print "Error moving items to trash."
  exit 1
fi
