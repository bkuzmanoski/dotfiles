#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Delete Desktop Files
# @raycast.packageName System
# @raycast.icon icons/delete.png
# @raycast.mode silent

tell application "Finder"
  delete (every item of folder (path to desktop folder))
end tell

return ""
