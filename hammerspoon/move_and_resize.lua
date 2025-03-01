local utils = require("utils")
local module = {}
local bindings = {}

module.moveAmount = 0
module.resizeAmount = 0
module.hotkeys = {
  moveUp = {},
  moveDown = {},
  moveLeft = {},
  moveRight = {},
  resizeUp = {},
  resizeDown = {},
  resizeLeft = {},
  resizeRight = {},
  grow = {},
  shrink = {}
}

local function getWindow(resizeable)
  local window = hs.window.focusedWindow()
  if not window or
      window:isFullscreen() or
      (resizeable and not window:isMaximizable()) or
      not window:isVisible() then
    utils.playAlert()
    return nil
  end

  return window
end

local function move(x, y)
  local window = getWindow(false)
  if not window then
    return
  end

  local frame = window:frame()
  frame.x = frame.x + x
  frame.y = frame.y + y
  window:setFrame(frame, 0)
end

local function resize(x, y)
  local window = getWindow(true)
  if not window then
    return
  end

  local frame = window:frame()
  frame.w = frame.w + x
  frame.h = frame.h + y
  window:setFrame(frame, 0)
end

local function scale(amount)
  local window = getWindow(true)
  if not window then
    return
  end

  local frame = window:frame()
  frame.x = frame.x - math.floor(amount / 2)
  frame.y = frame.y - math.floor(amount / 2)
  frame.w = frame.w + amount
  frame.h = frame.h + amount
  window:setFrame(frame, 0)
end

function module.init()
  local handlers = {
    -- Moving handlers
    moveUp = function() move(0, -module.moveAmount) end,
    moveDown = function() move(0, module.moveAmount) end,
    moveLeft = function() move(-module.moveAmount, 0) end,
    moveRight = function() move(module.moveAmount, 0) end,

    -- Resizing handlers
    resizeUp = function() resize(0, -module.resizeAmount) end,
    resizeDown = function() resize(0, module.resizeAmount) end,
    resizeLeft = function() resize(-module.resizeAmount, 0) end,
    resizeRight = function() resize(module.resizeAmount, 0) end,
    grow = function() scale(module.resizeAmount) end,
    shrink = function() scale(-module.resizeAmount) end
  }

  for name, hotkey in pairs(module.hotkeys) do
    if next(hotkey) and handlers[name] then
      bindings[name] = hs.hotkey.bind(
        hotkey.modifiers,
        hotkey.key,
        handlers[name],
        nil,
        handlers[name]
      )
    end
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
