local utils = require("utils")
local module = {}
local bindings = {}

module.moveHotkeys = {
  up = {},
  down = {},
  left = {},
  right = {}
}
module.resizeHotkeys = {
  up = {},
  down = {},
  left = {},
  right = {}
}
module.amount = 0

local function moveWindow(x, y)
  local window = hs.window.focusedWindow()
  if window and window:isVisible() and window:isStandard() then
    local frame = window:frame()
    frame.x = frame.x + x
    frame.y = frame.y + y
    window:setFrame(frame)
  end
end

local function resizeWindow(x, y)
  local window = hs.window.focusedWindow()
  if not window or not window:isVisible() or not window:isMaximizable() then
    utils.playAlert()
  end

  local frame = window:frame()
  frame.w = frame.w + x
  frame.h = frame.h + y
  window:setFrame(frame)
end

function module.init()
  if next(module.moveHotkeys.up) then
    bindings.up = hs.hotkey.bind(
      module.moveHotkeys.up.modifiers,
      module.moveHotkeys.up.key,
      function() moveWindow(0, -module.amount) end,
      nil,
      function() moveWindow(0, -module.amount) end
    )
  end
  if next(module.moveHotkeys.down) then
    bindings.down = hs.hotkey.bind(
      module.moveHotkeys.down.modifiers,
      module.moveHotkeys.down.key,
      function() moveWindow(0, module.amount) end,
      nil,
      function() moveWindow(0, module.amount) end
    )
  end
  if next(module.moveHotkeys.left) then
    bindings.left = hs.hotkey.bind(
      module.moveHotkeys.left.modifiers,
      module.moveHotkeys.left.key,
      function() moveWindow(-module.amount, 0) end,
      nil,
      function() moveWindow(-module.amount, 0) end
    )
  end
  if next(module.moveHotkeys.right) then
    bindings.right = hs.hotkey.bind(
      module.moveHotkeys.right.modifiers,
      module.moveHotkeys.right.key,
      function() moveWindow(module.amount, 0) end,
      nil,
      function() moveWindow(module.amount, 0) end
    )
  end
  if next(module.resizeHotkeys.up) then
    bindings.resizeUp = hs.hotkey.bind(
      module.resizeHotkeys.up.modifiers,
      module.resizeHotkeys.up.key,
      function() resizeWindow(0, -module.amount) end,
      nil,
      function() resizeWindow(0, -module.amount) end
    )
  end
  if next(module.resizeHotkeys.down) then
    bindings.resizeDown = hs.hotkey.bind(
      module.resizeHotkeys.down.modifiers,
      module.resizeHotkeys.down.key,
      function() resizeWindow(0, module.amount) end,
      nil,
      function() resizeWindow(0, module.amount) end
    )
  end
  if next(module.resizeHotkeys.left) then
    bindings.resizeLeft = hs.hotkey.bind(
      module.resizeHotkeys.left.modifiers,
      module.resizeHotkeys.left.key,
      function() resizeWindow(-module.amount, 0) end,
      nil,
      function() resizeWindow(-module.amount, 0) end
    )
  end
  if next(module.resizeHotkeys.right) then
    bindings.resizeRight = hs.hotkey.bind(
      module.resizeHotkeys.right.modifiers,
      module.resizeHotkeys.right.key,
      function() resizeWindow(module.amount, 0) end,
      nil,
      function() resizeWindow(module.amount, 0) end
    )
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
