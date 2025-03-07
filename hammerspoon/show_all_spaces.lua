local module = {}
local binding

module.hotkey = {}

function module.init()
  if next(module.hotkey) then
    binding = hs.hotkey.bind(module.hotkey.modifiers, module.hotkey.key, function()
      local mousePosition = hs.mouse.absolutePosition()
      hs.mouse.absolutePosition({ x = 10, y = 10 })
      hs.eventtap.keyStroke({ "fn", "ctrl" }, "up")
      hs.mouse.absolutePosition(mousePosition)
    end)
  end
end

function module.cleanup()
  if binding then
    binding:delete()
    binding = nil
  end
end

return module
