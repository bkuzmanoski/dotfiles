#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Send to Feedbin
# @raycast.mode silent
#
# Optional parameters:
# @raycast.packageName System
#
# Documentation:
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

-- Check if Chrome is running
tell application "System Events"
  set chromeRunning to (exists process "Google Chrome")
end tell

if not chromeRunning then
    return "Google Chrome is not running"
end if

-- Focus Chrome and copy URLs
tell application "Google Chrome" to activate
delay 0.2
tell application "System Events" to keystroke "e" using {shift down, command down}
delay 0.2

-- Run the Raycast extension to email selected text
do shell script "open \"raycast://extensions/peduarte/dash-off/email-form\""
delay 1
tell application "System Events" to keystroke "v" using command down
delay 0.2
tell application "System Events" to keystroke return using command down
