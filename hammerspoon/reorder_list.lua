local module = {}
local bindings = {}
local windowSubscriptions = {}
local clipboardData

module.hotkeys = {}
module.allowApps = {}

local function saveClipboard()
  clipboardData = hs.pasteboard.readAllData()
  hs.timer.usleep(100000)
end

local function restoreClipboard()
  hs.timer.usleep(100000)
  hs.pasteboard.writeAllData(clipboardData)
  clipboardData = nil
end

local function cutLine()
  hs.eventtap.keyStroke({ "command" }, "left", 5000)           -- Move cursor to beginning of line
  hs.eventtap.keyStroke({ "command", "shift" }, "right", 5000) -- Select text
  hs.eventtap.keyStroke({ "command" }, "x", 5000)              -- Cut text
  hs.eventtap.keyStroke({}, "delete", 5000)                    -- Remove empty line
end

local function moveLineUp()
  saveClipboard()
  cutLine()
  hs.eventtap.keyStroke({ "command" }, "left", 5000) -- Move cursor to beginning of line
  hs.eventtap.keyStroke({ "command" }, "v", 5000)    -- Paste text
  hs.eventtap.keyStroke({}, "return", 5000)          -- Insert newline
  hs.eventtap.keyStroke({}, "up", 5000)              -- Return cursor to the pasted line
  restoreClipboard()
end

local function moveLineDown()
  saveClipboard()
  cutLine()
  hs.eventtap.keyStroke({}, "down", 5000)             -- Move cursor down
  hs.eventtap.keyStroke({ "command" }, "right", 5000) -- Move cursor to end of line
  hs.eventtap.keyStroke({}, "return", 5000)           -- Insert newline
  hs.eventtap.keyStroke({ "command" }, "v", 5000)     -- Paste text
  hs.eventtap.keyStroke({ "command" }, "left", 5000)  -- Move cursor to the start of line
  restoreClipboard()
end

local function moveLine(direction)
  local window = hs.window.focusedWindow()
  if not window then
    return
  end

  local appName = window:application():name()
  for _, allowedApp in ipairs(module.allowApps) do
    if appName == allowedApp then
      if direction == "up" then
        moveLineUp()
      elseif direction == "down" then
        moveLineDown()
      end
      return
    end
  end
end

local function enableBindings()
  for _, binding in pairs(bindings) do
    binding:enable()
  end
end

local function disableBindings()
  for _, binding in pairs(bindings) do
    binding:disable()
  end
end

function module.init()
  local handlers = {
    moveLineUp = function() moveLine("up") end,
    moveLineDown = function() moveLine("down") end
  }

  if module.allowApps and #module.allowApps > 0 and next(module.hotkeys) then
    for _, appName in ipairs(module.allowApps) do
      windowSubscriptions[appName] = hs.window.filter.new(appName)
      windowSubscriptions[appName]:subscribe(hs.window.filter.windowFocused, enableBindings)
      windowSubscriptions[appName]:subscribe(hs.window.filter.windowUnfocused, disableBindings)
    end

    for action, hotkey in pairs(module.hotkeys) do
      if handlers[action] then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
        bindings[action]:disable()
      end
    end
  end
end

function module.cleanup()
  for _, windowSubscription in pairs(windowSubscriptions) do
    windowSubscription:unsubscribeAll()
    windowSubscription = nil
  end
  windowSubscriptions = {}

  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
