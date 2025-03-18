local module = {}
local binding

local function toggleSpacesOverview()
  -- Trigger mission control and move mouse to the top left corner to trigger the spaces overview
  local mousePosition = hs.mouse.absolutePosition()
  hs.mouse.absolutePosition({ x = 10, y = 10 })
  hs.eventtap.keyStroke({ "fn", "ctrl" }, "up", 0)
  hs.mouse.absolutePosition(mousePosition)
end

function module.init(config)
  if binding then module.cleanup() end

  if config.modifiers and config.key then
    binding = hs.hotkey.bind(config.modifiers, config.key, toggleSpacesOverview)
  end

  return module
end

function module.cleanup()
  if binding then binding:delete() end
  binding = nil
end

return module
