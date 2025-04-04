local utils = require("utils")
local module = {}
local bindings = {}
local topOffset, padding

local function moveToScreen(direction)
  local window = hs.window.focusedWindow()
  if not window:isStandard() or window:isFullscreen() then
    utils.playAlert()
    return
  end

  local fromScreen = window:screen()
  local toScreen
  if direction == "north" then
    toScreen = fromScreen:toNorth()
  elseif direction == "south" then
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
    local adjustedScreenFrame = utils.getAdjustedScreenFrame(toFrame, topOffset, padding)
    windowFrame = utils.getAdjustedWindowFrame(adjustedScreenFrame, windowFrame)
  end

  window:setFrame(windowFrame)
end

function module.init(config)
  if next(bindings) then module.cleanup() end

  if config and config.hotkeys then
    local handlers = {
      toNorth = "north",
      toSouth = "south"
    }
    for action, hotkey in pairs(config.hotkeys) do
      if handlers[action] then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, function() moveToScreen(handlers[action]) end)
      end
    end

    if next(bindings) then
      topOffset = config.topOffset or 0
      padding = config.padding or 0
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
