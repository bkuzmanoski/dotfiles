on getActiveTabData(closeSent)
  tell application "Google Chrome"
    if (count windows) > 0 then
      set activeTab to active tab of front window
      set tabURL to URL of activeTab

      if tabURL is not "chrome://newtab/" then
        set tabData to {{tabTitle:title of activeTab, tabURL:tabURL}}

        if closeSent then
          close activeTab
        end if

        return tabData
      end if
    end if
  end tell

  return {}
end getActiveTabData

on getAllTabsData(closeSent)
  set tabsData to {}
  set tabsToClose to {}

  tell application "Google Chrome"
    repeat with chromeWindow in windows
      repeat with tabRef in tabs of chromeWindow
        set currentTab to contents of tabRef
        set tabURL to URL of currentTab

        if tabURL is not "chrome://newtab/" then
          set end of tabsData to {tabTitle:title of currentTab, tabURL:tabURL}
          set end of tabsToClose to currentTab
        end if
      end repeat
    end repeat

    if closeSent then
      repeat with tabToClose in tabsToClose
        close tabToClose
      end repeat
    end if
  end tell

  return tabsData
end getAllTabsData

on formatMessageContent(tabsData)
  set messageContent to ""

  repeat with index from 1 to count of tabsData
    if index > 1 then
      set messageContent to messageContent & return & return
    end if

    set tabRecord to item index of tabsData
    set messageContent to messageContent & tabTitle of tabRecord & return & tabURL of tabRecord
  end repeat

  return messageContent
end formatMessageContent

on sendEmail(recipientAddress, messageSubject, messageContent)
  tell application "System Events"
    set mailWasRunning to exists processes where name is "Mail"
  end tell

  tell application "Mail"
    set newMessage to make new outgoing message with properties {subject:messageSubject, content:messageContent}

    tell newMessage
      make new to recipient with properties {address:recipientAddress}
      send
    end tell
  end tell

  if not mailWasRunning then
    do shell script "nohup zsh -c 'sleep 5 && osascript -e \"tell application \\\"Mail\\\" to quit\"' > /dev/null 2>&1 &"
  end if
end sendEmail

on run argv
  tell application "System Events"
    if not exists processes where name is "Google Chrome" then
      return
    end if
  end tell

  if count of argv < 1 then
    return "Recipient email address was not provided."
  end if

  set recipientEmail to item 1 of argv
  set activeOnly to false
  set closeSent to false

  repeat with arg in argv
    if contents of arg is "--active-only" then
      set activeOnly to true
    else if contents of arg is "--close-sent" then
      set closeSent to true
    end if
  end repeat

  if activeOnly then
    set messageSubject to "Tab from Mac"
    set tabsData to getActiveTabData(closeSent)
  else
    set messageSubject to "Tabs from Mac"
    set tabsData to getAllTabsData(closeSent)
  end if

  set tabCount to count of tabsData

  if tabCount = 0 then
    return
  end if

  set messageContent to formatMessageContent(tabsData)
  sendEmail(recipientEmail, messageSubject, messageContent)

  if tabCount = 1 then
    return "Sent tab"
  else
    return "Sent " & tabCount & " tabs"
  end if
end run
