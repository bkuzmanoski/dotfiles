#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Purge Downloads
# @raycast.mode silent

# Optional parameters:
# @raycast.packageName System

# Documentation:
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

# Get the Downloads folder path and ensure it exists
DOWNLOADS_DIR="${HOME}/Downloads"

if [[ ! -d "${DOWNLOADS_DIR}" ]]; then
  print "Downloads directory not found."
  exit 1
fi

# Check if there are any files/folders to move
if [[ -z "$(ls "${DOWNLOADS_DIR}")" ]]; then
  print "Downloads folder is already empty."
  exit 0
fi

# Move items to trash
osascript << EOD
  tell application "Finder"
    set downloadsFolder to POSIX file "${DOWNLOADS_DIR}" as alias
    delete (every item of folder downloadsFolder)
  end tell
EOD

if (( ! $? )); then
  print "Successfully moved items to trash."
else
  print "Error moving items to trash."
  exit 1
fi
