#!/usr/bin/osascript

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Clear Notifications
# @raycast.mode silent
#
# Optional parameters:
# @raycast.packageName System
#
# Documentation:
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski
#
# Tweaked version of the original script by Bartosz Petryński (https://github.com/bpetrynski)
# https://github.com/bpetrynski/alfred-notification-dismisser

property closeActionSet : {"Close", "Clear All"}
property notificationsCleared : 0

on toggleNotificationCenter()
  tell application "System Events"
    key down 63
    key down "n"
    key up "n"
    key up 63
  end tell
  delay 0.1
end toggleNotificationCenter

on clearNotification(elemRef)
  tell application "System Events"
    try
      set theActions to actions of elemRef
      repeat with act in theActions
        if description of act is in closeActionSet then
          perform act
          set notificationsCleared to notificationsCleared + 1
          return true
        end if
      end repeat
    end try
  end tell
  return false
end clearNotification

-- Recursively search for and close notifications
on searchAndClearNotifications(element)
  tell application "System Events"
    try
      set subElements to UI elements of element
      repeat with subElement in subElements
        if my searchAndClearNotifications(subElement) then
          return true
        end if
      end repeat
    end try

    if my clearNotification(element) then
      return true
    end if
  end tell
  return false
end searchAndClearNotifications

on run
  my toggleNotificationCenter()
  try
    tell application "System Events"
      if not (exists process "NotificationCenter") then
        my toggleNotificationCenter()
        return "Notification Center process not found"
      end if

      tell process "NotificationCenter"
        if not (exists window "Notification Center") then
          my toggleNotificationCenter()
          return "Notification Center window not found"
        end if

        set notificationWindow to window "Notification Center"
        repeat
          try
            if not my searchAndClearNotifications(notificationWindow) then
              exit repeat
            end if
            delay 0.1
          on error errMsg
            my toggleNotificationCenter()
            return "Error: " & errMsg
          end try
        end repeat
      end tell
    end tell
  on error errMsg
    my toggleNotificationCenter()
    return "Error: " & errMsg
  end try

  my toggleNotificationCenter()

  if notificationsCleared > 0 then
    return "Notifications cleared"
  else
    return "No notifications found"
  end if
end
