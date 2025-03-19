#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Send Tabs to Feedbin
# @raycast.mode silent
# @raycast.packageName Google Chrome
# @raycast.icon icons/send-tabs-to-feedbin.png

try
  set chromeRunning to (do shell script "ps -ax | grep -v 'grep' | grep 'Google Chrome' | wc -l") as integer
  if chromeRunning is 0 then
    return "Google Chrome is not running"
  end if
on error
  return "Google Chrome is not running"
end try

tell application "Google Chrome"
  if (count of windows) is 0 then
    return "Google Chrome has no open windows"
  end if

  set windowCount to count windows
  set urlCount to 0
  set urlList to ""

  activate

  repeat with windowIndex from 1 to windowCount
    set currentWindow to window windowIndex
    set tabCount to count tabs of currentWindow

    repeat with tabIndex from 1 to tabCount
      set currentTab to tab tabIndex of currentWindow
      set tabURL to URL of currentTab

      if tabURL is not "chrome://newtab/" then
        set tabTitle to title of currentTab
        set urlList to urlList & tabTitle & return & tabURL & return & return
        set urlCount to urlCount + 1
      end if
    end repeat
  end repeat

  if urlCount is 0 then
    return "Google Chrome has no open tabs"
  end if

  set the clipboard to urlList
end tell

delay 1
do shell script "open 'raycast://extensions/peduarte/dash-off/email-form'"
delay 1.5

tell application "System Events"
  keystroke "v" using {command down}
  delay 0.5
  keystroke return using {command down}
end tell
