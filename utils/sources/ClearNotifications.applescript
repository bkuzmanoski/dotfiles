on clearNotifications(uiElement)
  set didClear to false

  tell application "System Events"
    if my clearNotification(uiElement) then
      set didClear to true
    else
      repeat with childElement in UI elements of uiElement
        if my clearNotifications(childElement) then
          set didClear to true
        end if
      end repeat
    end if
  end tell

  return didClear
end clearNotifications

on clearNotification(notificationElement)
  tell application "System Events"
    repeat with notificationAction in actions of notificationElement
      if description of notificationAction is in {"Close", "Clear All"} then
        perform notificationAction
        return true
      end if
    end repeat
  end tell

  return false
end clearNotification

on run
  tell application "System Events"
    tell process "NotificationCenter"
      if not count of windows > 0 then
        key down 63
        key down "n"
        key up "n"
        key up 63
      end if

      my clearNotifications(window "Notification Center")

      if count of windows > 0 then
        key code 53
      end if
    end tell
  end tell
end run
