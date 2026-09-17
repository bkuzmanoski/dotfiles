local module = {}

local utils = require("utils")

local targetWindow = {
  frontmost = "frontmost",
  left = "left",
  right = "right"
}
local minimumWindowSize = 100
local alignmentTolerance = 8

local bindings = {}
local excludedWindowTitles

local function activateWindow(window)
  local app = window:application()

  if app and app:pid() >= 0 then
    window:focus()
    return
  end

  local appElement = hs.axuielement.applicationElementForPID(window:pid())

  window:becomeMain()

  if appElement then
    appElement:setAttributeValue("AXFrontmost", true)
  end
end

local function focusWindow(target)
  local windows = utils.getOrderedWindows()

  if not windows or #windows == 0 then
    return
  end

  local screen = hs.screen.mainScreen()
  local filteredWindows = hs.fnutils.ifilter(windows, function(window)
    local frame = window:frame()
    local subrole = window:subrole()

    return
        window:screen() == screen and
        not window:isFullscreen() and
        not excludedWindowTitles[window:title()] and
        subrole ~= "AXFloatingWindow" and
        subrole ~= "AXUnknown" and
        frame.w > minimumWindowSize and
        frame.h > minimumWindowSize
  end)

  if #filteredWindows == 0 then
    return
  end

  local frontmostWindow = filteredWindows[1]

  if target == targetWindow.frontmost or #filteredWindows == 1 then
    activateWindow(frontmostWindow)
    return
  end

  table.sort(filteredWindows, function(windowA, windowB)
    local frameA = windowA:frame()
    local frameB = windowB:frame()

    local xA = math.floor(frameA.x / alignmentTolerance)
    local xB = math.floor(frameB.x / alignmentTolerance)

    if xA ~= xB then
      return xA < xB
    end

    local yA = math.floor(frameA.y / alignmentTolerance)
    local yB = math.floor(frameB.y / alignmentTolerance)

    if yA ~= yB then
      return yA < yB
    end

    return windowA:id() < windowB:id()
  end)

  local focusedWindow = hs.window.focusedWindow() or frontmostWindow
  local currentIndex =
      hs.fnutils.indexOf(filteredWindows, focusedWindow) or
      hs.fnutils.indexOf(filteredWindows, frontmostWindow) or
      1
  local nextIndex

  if target == targetWindow.left then
    nextIndex = ((currentIndex - 2 + #filteredWindows) % #filteredWindows) + 1
  elseif target == targetWindow.right then
    nextIndex = (currentIndex % #filteredWindows) + 1
  end

  activateWindow(filteredWindows[nextIndex])
end

function module.init(config)
  if next(bindings) then
    module.cleanup()
  end

  if not config or not config.hotkeys then
    return module
  end

  local handlers = {
    frontmost = function()
      focusWindow(targetWindow.frontmost)
    end,
    left = function()
      focusWindow(targetWindow.left)
    end,
    right = function()
      focusWindow(targetWindow.right)
    end
  }

  for action, hotkey in pairs(config.hotkeys) do
    if hotkey.modifiers and hotkey.key and handlers[action] then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
    end
  end

  excludedWindowTitles = {}

  for _, windowTitle in ipairs(config.excludeWindowTitles or {}) do
    excludedWindowTitles[windowTitle] = true
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end

  bindings = {}
end

return module
