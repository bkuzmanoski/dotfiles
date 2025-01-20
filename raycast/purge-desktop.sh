#!/bin/bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Purge Desktop
# @raycast.mode silent

# Optional parameters:
# @raycast.packageName Finder Utilities

# Documentation:
# @raycast.author britown
# @raycast.authorURL https://github.com/bkuzmanoski

# Get the Desktop folder path and ensure it exists
desktop=~/Desktop
if [[ ! -d "$desktop" ]]; then
  echo "Desktop directory not found"
  exit 1
fi

# Check if there are any files/folders to move
if [[ -z "$(ls $desktop)" ]]; then
  echo "Desktop folder is already empty"
  exit 0
fi

# Move items to trash
osascript <<EOD
  tell application "Finder"
    set desktopFolder to POSIX file "$desktop" as alias
    delete (every item of folder desktopFolder)
  end tell
EOD

if [ $? -eq 0 ]; then
  echo "Successfully moved items to trash"
else
  echo "Error moving items to trash"
  exit 1
fi