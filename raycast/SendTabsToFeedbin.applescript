#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Send Tabs to Feedbin
# @raycast.mode silent
# @raycast.packageName Personal
# @raycast.icon icons/send-tabs-to-feedbin.png

tell application "System Events"
  if not (exists process "Google Chrome") then
    -- return "Google Chrome is not running"
    return "" -- This is slow so just return silently
  end if
end tell

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
    return "No tabs found"
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
