#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Purge Downloads
# @raycast.mode silent

# Optional parameters:
# @raycast.packageName Finder Utilities

# Documentation:
# @raycast.author britown
# @raycast.authorURL https://github.com/bkuzmanoski

# Get the Downloads folder path and ensure it exists
downloads=~/Downloads
if [[ ! -d "$downloads" ]]; then
  echo "Downloads directory not found"
  exit 1
fi

# Check if there are any files/folders to move
if [[ -z "$(ls $downloads)" ]]; then
  echo "Downloads folder is already empty"
  exit 0
fi

# Move items to trash
osascript <<EOD
  tell application "Finder"
    set downloadsFolder to POSIX file "$downloads" as alias
    delete (every item of folder downloadsFolder)
  end tell
EOD

if [ $? -eq 0 ]; then
  echo "Successfully moved items to trash"
else
  echo "Error moving items to trash"
  exit 1
fi