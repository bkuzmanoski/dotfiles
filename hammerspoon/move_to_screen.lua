local utils = require("utils")
local module = {}
local bindings = {}

module.topOffset = 0
module.padding = 0
module.hotkeys = {
  up = {},
  down = {}
}

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
  if next(module.hotkeys.up) then
    bindings.resizeUp = hs.hotkey.bind(module.hotkeys.up.modifiers, module.hotkeys.up.key, function()
      moveToScreen("up")
    end)
  end
  if next(module.hotkeys.down) then
    bindings.resizeDown = hs.hotkey.bind(module.hotkeys.down.modifiers, module.hotkeys.down.key, function()
      moveToScreen("down")
    end)
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
