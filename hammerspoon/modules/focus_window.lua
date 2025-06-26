local module = {}
local bindings = {}
local windowFilter

local targetWindow = {
  frontmost = "frontmost",
  left = "left",
  right = "right"
}

local function focusWindow(target)
  local windows = hs.window.orderedWindows()
  if not windows or #windows == 0 then return end

  local screen = hs.screen.mainScreen()
  local windowsOnScreen = hs.fnutils.ifilter(windows, function(window)
    return window:screen() == screen and not window:isFullscreen()
  end)
  if #windowsOnScreen == 0 then return end

  local focusedWindow = hs.window.focusedWindow()
  if target == targetWindow.frontmost or not focusedWindow or #windowsOnScreen == 1 then
    windowsOnScreen[1]:focus()
    return
  end

  table.sort(windowsOnScreen, function(a, b)
    local frameA = a:frame()
    local frameB = b:frame()
    if math.abs(frameA.x - frameB.x) > 5 then return frameA.x < frameB.x end
    if math.abs(frameA.y - frameB.y) > 5 then return frameA.y < frameB.y end
    return a:id() < b:id()
  end)

  local currentIndex = hs.fnutils.indexOf(windowsOnScreen, focusedWindow)
  if not currentIndex then
    windowsOnScreen[1]:focus()
    return
  end

  local nextIndex
  if target == targetWindow.left then
    nextIndex = currentIndex == 1 and #windowsOnScreen or currentIndex - 1
  elseif target == targetWindow.right then
    nextIndex = currentIndex == #windowsOnScreen and 1 or currentIndex + 1
  end

  windowsOnScreen[nextIndex]:focus()
end

function module.init(config)
  if next(bindings) or windowFilter then module.cleanup() end

  if not config or not config.hotkeys then return module end

  local handlers = {
    frontmost = function() focusWindow(targetWindow.frontmost) end,
    left = function() focusWindow(targetWindow.left) end,
    right = function() focusWindow(targetWindow.right) end
  }
  for action, hotkey in pairs(config.hotkeys) do
    if hotkey.modifiers and hotkey.key and handlers[action] then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action], nil, handlers[action])
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
  windowFilter = nil
end

return module
