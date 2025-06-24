property feedbinEmail : "bwilw@feedb.in"

on isAppRunning(appName)
  try
    set processCount to (do shell script "ps -ax | grep -v 'grep' | grep '" & appName & "' | wc -l") as integer
    return processCount > 0
  on error
    return false
  end try
end isAppRunning

on getActiveTabURL()
  tell application "Google Chrome"
    if (count windows) > 0 then
      set frontWindow to front window
      set activeTab to active tab of frontWindow
      set tabURL to URL of activeTab
      set tabTitle to title of activeTab

      if tabURL is not "chrome://newtab/" then
        set tabContent to tabTitle & return & tabURL
        return {content:tabContent, urlCount:1}
      end if
    end if
  end tell

  return {content:"", urlCount:0}
end getActiveTab

on getAllTabURLs()
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

  if urlCount > 0 then
    return {content:urlList, urlCount:urlCount}
  end if

  return {content:"", urlCount:0}
end getAllTabs

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

on run argv
  set mode to ""
  if (count of argv) > 0 then
    set mode to item 1 of argv
  end if

  if not isAppRunning("Google Chrome.app") then
    return "Google Chrome is not running"
  end if

  if mode is "--active-only" then
    set urlData to getActiveTabURL()
    set emailSubject to "Tab from macOS"
  else
    set urlData to getAllTabURLs()
    set emailSubject to "Tabs from macOS"
  end if

  set urlCount to urlCount of urlData
  if urlCount = 0 then
    return "Google Chrome has no open tabs"
  end if

  sendEmail(feedbinEmail, emailSubject, (content of urlData))

  if mode is "--active-only" then
    return "Sent active tab to Feedbin"
  else
    if urlCount = 1 then
      return "Sent 1 tab to Feedbin"
    else
      return "Sent " & urlCount & " tabs to Feedbin"
    end if
  end if
end run
