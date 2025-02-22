local module = {}

module.amount = 8
module.moveHotkeys = {
  up = { modifiers = { "shift", "option", "command" }, key = "p" },
  down = { modifiers = { "shift", "option", "command" }, key = ";" },
  left = { modifiers = { "shift", "option", "command" }, key = "l" },
  right = { modifiers = { "shift", "option", "command" }, key = "'" }
}
module.resizeHotkeys = {
  up = { modifiers = { "control", "option", "command" }, key = "p" },
  down = { modifiers = { "control", "option", "command" }, key = ";" },
  left = { modifiers = { "control", "option", "command" }, key = "l" },
  right = { modifiers = { "control", "option", "command" }, key = "'" }
}

local bindings = {}
local alertSound = hs.sound.getByFile("/System/Library/Sounds/Tink.aiff")

local function playAlert()
  if alertSound then
    alertSound:play()
  end
end

local function moveWindow(x, y)
  local window = hs.window.focusedWindow()
  if window then
    local frame = window:frame()
    frame.x = frame.x + x
    frame.y = frame.y + y
    window:setFrame(frame)
  end
end

local function resizeWindow(x, y)
  local window = hs.window.focusedWindow()
  if window then
    -- Check if the window is resizable
    if not window:isMaximizable() then
      playAlert()
      return
    end

    local frame = window:frame()
    frame.w = frame.w + x
    frame.h = frame.h + y
    window:setFrame(frame)
  end
end

function module.init()
  -- Move key bindings
  bindings.up = hs.hotkey.bind(
    module.moveHotkeys.up.modifiers,
    module.moveHotkeys.up.key,
    function() moveWindow(0, -module.amount) end,
    nil,
    function() moveWindow(0, -module.amount) end
  )
  bindings.down = hs.hotkey.bind(
    module.moveHotkeys.down.modifiers,
    module.moveHotkeys.down.key,
    function() moveWindow(0, module.amount) end,
    nil,
    function() moveWindow(0, module.amount) end
  )
  bindings.left = hs.hotkey.bind(
    module.moveHotkeys.left.modifiers,
    module.moveHotkeys.left.key,
    function() moveWindow(-module.amount, 0) end,
    nil,
    function() moveWindow(-module.amount, 0) end
  )
  bindings.right = hs.hotkey.bind(
    module.moveHotkeys.right.modifiers,
    module.moveHotkeys.right.key,
    function() moveWindow(module.amount, 0) end,
    nil,
    function() moveWindow(module.amount, 0) end
  )

  -- Resize key bindings
  bindings.resizeUp = hs.hotkey.bind(
    module.resizeHotkeys.up.modifiers,
    module.resizeHotkeys.up.key,
    function() resizeWindow(0, -module.amount) end,
    nil,
    function() resizeWindow(0, -module.amount) end
  )
  bindings.resizeDown = hs.hotkey.bind(
    module.resizeHotkeys.down.modifiers,
    module.resizeHotkeys.down.key,
    function() resizeWindow(0, module.amount) end,
    nil,
    function() resizeWindow(0, module.amount) end
  )
  bindings.resizeLeft = hs.hotkey.bind(
    module.resizeHotkeys.left.modifiers,
    module.resizeHotkeys.left.key,
    function() resizeWindow(-module.amount, 0) end,
    nil,
    function() resizeWindow(-module.amount, 0) end
  )
  bindings.resizeRight = hs.hotkey.bind(
    module.resizeHotkeys.right.modifiers,
    module.resizeHotkeys.right.key,
    function() resizeWindow(module.amount, 0) end,
    nil,
    function() resizeWindow(module.amount, 0) end
  )
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
