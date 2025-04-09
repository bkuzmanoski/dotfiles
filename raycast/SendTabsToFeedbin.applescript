#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Send Tabs to Feedbin
# @raycast.mode silent
# @raycast.packageName Google Chrome
# @raycast.icon icons/send-tabs-to-feedbin.png

property feedbinEmail : "bwilw@feedb.in"
property emailSubject : "Mac Tabs"

on isAppRunning(appName)
  try
    set processCount to (do shell script "ps -ax | grep -v 'grep' | grep '" & appName & "' | wc -l") as integer
    return processCount > 0
  on error
    return false
  end try
end isAppRunning

on getTabURLs()
  set urlCount to 0
  set urlList to ""

  tell application "Google Chrome"
    set windowCount to count windows

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
  end tell

  return {urlCount:urlCount, urlList:urlList}
end getTabURLs

on sendEmail(toAddress, emailSubject, body)
  set mailWasRunning to isAppRunning("Mail.app")

  tell application "Mail"
    set newMessage to make new outgoing message with properties {subject:emailSubject, content:body}
    tell newMessage
      make new to recipient with properties {address:toAddress}
      send
    end tell
  end tell

  if not mailWasRunning then
    do shell script "nohup zsh -c 'sleep 5 && osascript -e \"tell application \\\"Mail\\\" to quit\"' > /dev/null 2>&1 &"
  end if
end sendEmail

on run
  if not isAppRunning("Google Chrome.app") then
    return "Google Chrome is not running"
  end if

  set urls to getTabURLs()
  set urlCount to urlCount of urls
  set urlList to urlList of urls

  if urlCount is 0 then
    return "Google Chrome has no open tabs"
  end if

  sendEmail(feedbinEmail, emailSubject, urlList)

  if urlCount = 1 then
    return "Sent " & urlCount & " tab to Feedbin"
  else
    return "Sent " & urlCount & " tabs to Feedbin"
  end if
end
