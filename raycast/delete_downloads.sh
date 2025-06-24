#!/usr/bin/osascript

# @raycast.title Delete Downloads
# @raycast.packageName Finder
# @raycast.icon icons/delete.png

# @raycast.mode silent

# @raycast.schemaVersion 1

tell application "Finder"
  delete (every item of folder (path to downloads folder))
end tell

return ""
