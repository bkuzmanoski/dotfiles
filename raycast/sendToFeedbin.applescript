#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Send to Feedbin
# @raycast.mode silent
# @raycast.packageName Personal
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

tell application "System Events"
  if not (exists process "Google Chrome") then
    return "Google Chrome is not running"
  end if
end tell

tell application "Google Chrome"
  if (count of windows) is 0 then
    return "Google Chrome has no open windows"
  end if
end tell

tell application "Google Chrome" to activate
delay 0.5
tell application "System Events" to keystroke "e" using {shift down, command down}
delay 0.5
do shell script "open 'raycast://extensions/peduarte/dash-off/email-form'"
delay 1
tell application "System Events" to keystroke "v" using command down
tell application "System Events" to keystroke return using command down
