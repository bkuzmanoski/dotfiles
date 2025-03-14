local utils = require("utils")
local module = {}
local bindings = {}

module.topOffset = 0
module.padding = 0
module.hotkeys = {}

local function moveToScreen(direction)
  local window = hs.window.focusedWindow()
  if window:isFullscreen() then
    utils.playAlert()
    return
  end

  local fromScreen = window:screen()
  local toScreen
  if direction == "up" then
    toScreen = fromScreen:toNorth()
  elseif direction == "down" then
    toScreen = fromScreen:toSouth()
  end
  if not toScreen then
    utils.playAlert()
    return
  end

  local fromFrame = fromScreen:fullFrame()
  local toFrame = toScreen:fullFrame()
  local windowFrame = window:frame()
  local fromCenter = {
    x = fromFrame.x + fromFrame.w / 2,
    y = fromFrame.y + fromFrame.h / 2
  }
  local toCenter = {
    x = toFrame.x + toFrame.w / 2,
    y = toFrame.y + toFrame.h / 2
  }
  local offset = {
    x = windowFrame.x + (windowFrame.w / 2) - fromCenter.x,
    y = windowFrame.y + (windowFrame.h / 2) - fromCenter.y
  }
  windowFrame.x = toCenter.x + offset.x - (windowFrame.w / 2)
  windowFrame.y = toCenter.y + offset.y - (windowFrame.h / 2)

  if window:isMaximizable() then
    windowFrame = utils.getAdjustedWindowFrame(toFrame, windowFrame, module.topOffset, module.padding)
  end

  window:setFrame(windowFrame)
end

function module.init()
  for direction, hotkey in pairs(module.hotkeys) do
    bindings[direction] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, function() moveToScreen(direction) end)
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
