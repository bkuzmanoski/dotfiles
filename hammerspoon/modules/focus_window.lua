local module = {}
local bindings = {}

local targetWindow = {
  frontmost = "frontmost",
  left = "left",
  right = "right"
}

local validSubroles = {
  ["AXStandardWindow"] = true,
  ["AXDialog"] = true,
  ["AXSystemDialog"] = true,
  ["AXFloatingWindow"] = true,
  ["AXSystemFloatingWindow"] = true
}

local sortingTolerance = 8

local function focusWindow(target)
  local windows = hs.window.orderedWindows()
  if not windows or #windows == 0 then return end

  local screen = hs.screen.mainScreen()
  local windowsOnScreen = hs.fnutils.ifilter(windows, function(window)
    return window:screen() == screen and not window:isFullscreen() and validSubroles[window:subrole()]
  end)
  if #windowsOnScreen == 0 then return end

  if target == targetWindow.frontmost or #windowsOnScreen == 1 then
    windowsOnScreen[1]:focus()
    return
  end

  table.sort(windowsOnScreen, function(windowA, windowB)
    local frameA = windowA:frame()
    local frameB = windowB:frame()

    local xA = math.floor(frameA.x / sortingTolerance)
    local xB = math.floor(frameB.x / sortingTolerance)
    if xA ~= xB then return xA < xB end

    local yA = math.floor(frameA.y / sortingTolerance)
    local yB = math.floor(frameB.y / sortingTolerance)
    if yA ~= yB then return yA < yB end

    return windowA:id() < windowB:id()
  end)

  local focusedWindow = hs.window.frontmostWindow() or windowsOnScreen[1]
  local currentIndex = hs.fnutils.indexOf(windowsOnScreen, focusedWindow) or 1
  local nextIndex
  if target == targetWindow.left then
    nextIndex = ((currentIndex - 2 + #windowsOnScreen) % #windowsOnScreen) + 1
  elseif target == targetWindow.right then
    nextIndex = (currentIndex % #windowsOnScreen) + 1
  end

  windowsOnScreen[nextIndex]:focus()
end

function module.init(config)
  if next(bindings) then module.cleanup() end

  if not config or not config.hotkeys then return module end

  local handlers = {
    frontmost = function() focusWindow(targetWindow.frontmost) end,
    left = function() focusWindow(targetWindow.left) end,
    right = function() focusWindow(targetWindow.right) end
  }
  for action, hotkey in pairs(config.hotkeys) do
    if hotkey.modifiers and hotkey.key and handlers[action] then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
