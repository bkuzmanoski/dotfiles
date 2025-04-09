#!/usr/bin/osascript

# @raycast.schemaVersion 1
# @raycast.title Clear Notifications
# @raycast.mode silent
# @raycast.packageName System
# @raycast.icon icons/clear-notifications.png

property clearActions : {"Close", "Clear All"}
property notificationsCleared : 0

on isNotificationCenterOpen()
  tell application "System Events"
    try
      tell process "NotificationCenter"
        set focusedElements to UI elements whose focused is true

        if (count of focusedElements) > 0 then
          return true
        end if
      end tell
    on error
      return false
    end try
  end tell
  return false
end isNotificationCenterOpen

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

on traverseNotifications(element)
  tell application "System Events"
    try
      set subElements to UI elements of element

      repeat with subElement in subElements
        if my traverseNotifications(subElement) then
          return true
        end if
      end repeat
    end try

    if my clearNotification(element) then
      return true
    end if
  end tell
  return false
end traverseNotifications

on run
  try
    tell application "System Events"
      if not my isNotificationCenterOpen() then
        key down 63
        key down "n"
        key up "n"
        key up 63
        delay 0.5
      end if

      tell process "NotificationCenter"
        set notificationCenterWindow to window "Notification Center"

        repeat
          if not my traverseNotifications(notificationCenterWindow) then
            exit repeat
          end if
        end repeat
      end tell

      if my isNotificationCenterOpen() then
        key code 53
      end if
    end tell
  on error errMsg
    return "Error: " & errMsg
  end try

  if notificationsCleared > 0 then
    return "Notifications cleared"
  else
    return "No notifications found"
  end if
end
