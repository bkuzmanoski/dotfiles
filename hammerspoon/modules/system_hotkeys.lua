local module = {}
local bindings = {}

local actions = {
  focusDock = function() hs.eventtap.keyStroke({ "fn", "ctrl" }, "f3") end,
  focusMenuBar = function() hs.eventtap.keyStroke({ "fn", "ctrl" }, "f2") end,
  toggleLaunchpad = hs.spaces.toggleLaunchPad,
  toggleMissionControl = function()
    local mousePosition = hs.mouse.absolutePosition()
    hs.mouse.absolutePosition({ x = 10, y = 10 })
    hs.eventtap.keyStroke({ "fn", "ctrl" }, "up", 0)
    hs.mouse.absolutePosition(mousePosition)
  end,
  toggleAppExpose = function() hs.spaces.toggleAppExpose() end,
  toggleShowDesktop = function() hs.spaces.toggleShowDesktop() end,
  toggleControlCenter = function() hs.eventtap.keyStroke({ "fn" }, "c") end,
  toggleNotificationCenter = function() hs.eventtap.keyStroke({ "fn" }, "n") end,
  goToSpaceLeft = function() hs.eventtap.keyStroke({ "fn", "ctrl" }, "left") end,
  goToSpaceRight = function() hs.eventtap.keyStroke({ "fn", "ctrl" }, "right") end,
  goToSpaceN = function(n) hs.eventtap.keyStroke({ "ctrl" }, tostring(n), 0) end
}

function module.init(config)
  if next(bindings) then module.cleanup() end

  if config then
    for action, hotkey in pairs(config) do
      if actions[action] then
        if action == "goToSpaceN" then
          for n = 1, 9 do
            bindings[action .. n] = hs.hotkey.bind(hotkey.modifiers, tostring(n), function() actions[action](n) end)
          end
        else
          bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, actions[action])
        end
      end
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
