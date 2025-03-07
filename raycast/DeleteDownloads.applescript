#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Delete Downloads
# @raycast.mode silent
# @raycast.packageName System
# @raycast.icon icons/delete.png

tell application "Finder"
  delete (every item of folder (path to downloads folder))
end tell

return ""
