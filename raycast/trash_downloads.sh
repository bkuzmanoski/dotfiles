#!/bin/zsh

# @raycast.schemaVersion 1
# @raycast.title Trash Downloads
# @raycast.mode silent
# @raycast.packageName System
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

DOWNLOADS_DIR="${HOME}/Downloads"

if [[ -z "$(ls "${DOWNLOADS_DIR}")" ]]; then
  print "Downloads folder is already empty"
  return
fi

output=$(osascript << EOD
  tell application "Finder"
    set downloadsFolder to POSIX file "${DOWNLOADS_DIR}" as alias
    delete (every item of folder downloadsFolder)
  end tell
EOD
)

if [[ ${?} -eq 0 ]]; then
  print "Successfully moved items to trash"
else
  print "Error: ${output}"
  return 1
fi
