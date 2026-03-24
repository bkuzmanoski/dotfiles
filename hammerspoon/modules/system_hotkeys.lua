local module = {}

local bindings = {}

function module.init(config)
  if next(bindings) then
    module.cleanup()
  end

  if not config then
    return module
  end

  local handlers = {
    focusMenuBar = function()
      hs.eventtap.keyStroke({ "fn", "ctrl" }, "f2")
    end,
    focusDock = function()
      hs.eventtap.keyStroke({ "fn", "ctrl" }, "f3")
    end,
    toggleLaunchpad = hs.spaces.toggleLaunchPad,
    toggleMissionControl = function()
      local mousePosition = hs.mouse.absolutePosition()
      hs.mouse.absolutePosition({ x = 10, y = 10 })
      hs.spaces.toggleMissionControl()
      hs.timer.doAfter(0.05, function()
        hs.mouse.absolutePosition(mousePosition)
      end)
    end,
    toggleAppExpose = hs.spaces.toggleAppExpose,
    toggleShowDesktop = hs.spaces.toggleShowDesktop,
    toggleControlCenter = function()
      hs.eventtap.keyStroke({ "fn" }, "c")
    end,
    toggleNotificationCenter = function()
      hs.eventtap.keyStroke({ "fn" }, "n")
    end
  }

  for action, hotkey in pairs(config) do
    if handlers[action] then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
    end
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
