#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Clear Notifications
# @raycast.mode silent
# @raycast.packageName System
# @raycast.author Britown
# @raycast.authorURL https://github.com/bkuzmanoski

property clearActions : {"Close", "Clear All"}
property notificationsCleared : 0

on toggleNotificationCenter()
  tell application "System Events"
    key down 63
    key down "n"
    key up "n"
    key up 63
  end tell
end toggleNotificationCenter

on clearNotification(notification)
  tell application "System Events"
    try
      set theActions to actions of notification
      repeat with act in theActions
        if description of act is in clearActions then
          perform act
          set notificationsCleared to notificationsCleared + 1
          return true
        end if
      end repeat
    end try
  end tell
  return false
end clearNotification

on traverseAndClearNotifications(element)
  tell application "System Events"
    try
      set subElements to UI elements of element
      repeat with subElement in subElements
        if my traverseAndClearNotifications(subElement) then
          return true
        end if
      end repeat
    end try
    if my clearNotification(element) then
      return true
    end if
  end tell
  return false
end traverseAndClearNotifications

on run
  try
    tell application "System Events"
      tell process "NotificationCenter"
        if not (exists window "Notification Center") then
          my toggleNotificationCenter()
        end if
        set notificationCenterWindow to window "Notification Center"
        repeat
          try
            if not my traverseAndClearNotifications(notificationCenterWindow) then
              exit repeat
            end if
          on error errMsg
            return "Error: " & errMsg
          end try
        end repeat
      end tell
    end tell
  on error errMsg
    return "Error: " & errMsg
  end try
  my toggleNotificationCenter()
  if notificationsCleared > 0 then
    return "Notifications cleared"
  else
    return "No notifications found"
  end if
end
