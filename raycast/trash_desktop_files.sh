#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Trash Desktop Files
# @raycast.mode silent
# @raycast.packageName System
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

DESKTOP_DIR="${HOME}/Desktop"

if [[ -z "$(ls "${DESKTOP_DIR}")" ]]; then
  print "Desktop folder is already empty"
  return
fi

output=$(osascript << EOD
  tell application "Finder"
    set desktopFolder to POSIX file "${DESKTOP_DIR}" as alias
    delete (every item of folder desktopFolder)
  end tell
EOD
)

if [[ ${?} -eq 0 ]]; then
  print "Successfully moved items to trash"
else
  print "Error: ${output}"
  return 1
fi
