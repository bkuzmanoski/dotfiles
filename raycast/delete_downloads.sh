#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Delete Downloads
# @raycast.packageName System
# @raycast.icon icons/delete.png
# @raycast.mode silent

tell application "Finder"
  delete (every item of folder (path to downloads folder))
end tell

return ""
