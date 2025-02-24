#!/bin/zsh

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Trash Downloads
# @raycast.mode silent
#
# Optional parameters:
# @raycast.packageName System
#
# Documentation:
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

# Get the Downloads folder path and ensure it exists
downloads_dir="${HOME}/Downloads"

if [[ ! -d "${downloads_dir}" ]]; then
  print "Downloads folder not found"
  exit 1
fi

# Check if there are any files/folders to move
if [[ -z "$(ls "${downloads_dir}")" ]]; then
  print "Downloads folder is already empty"
  exit 0
fi

# Move items to trash
output=$(osascript << EOD
  tell application "Finder"
    set downloadsFolder to POSIX file "${downloads_dir}" as alias
    delete (every item of folder downloadsFolder)
  end tell
EOD
)

if [[ $? -eq 0 ]]; then
  print "Successfully moved items to trash"
else
  print "Error moving items to trash: ${output}"
  exit 1
fi
