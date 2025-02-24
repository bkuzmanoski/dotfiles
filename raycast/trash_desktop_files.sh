#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Trash Desktop Files
# @raycast.mode silent
#
# Optional parameters:
# @raycast.packageName System
#
# Documentation:
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

# Get the Desktop folder path and ensure it exists
desktop_dir="${HOME}/Desktop"

if [[ ! -d "${desktop_dir}" ]]; then
  print "Desktop folder not found"
  exit 1
fi

# Check if there are any files/folders to move
if [[ -z "$(ls "${desktop_dir}")" ]]; then
  print "Desktop folder is already empty"
  exit 0
fi

# Move items to trash
output=$(osascript << EOD
  tell application "Finder"
    set desktopFolder to POSIX file "${desktop_dir}" as alias
    delete (every item of folder desktopFolder)
  end tell
EOD
)

if [[ $? -eq 0 ]]; then
  print "Successfully moved items to trash"
else
  print "Error moving items to trash: ${output}"
  exit 1
fi
