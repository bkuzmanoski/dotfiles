local module = {}

local bindings = {}

local function triggerSpaceSwitch(argument)
  hs.distributednotifications.post(
    "industries.britown.SwitchToSpace.command",
    nil,
    { arguments = { tostring(argument) } }
  )
end

function module.init(config)
  if next(bindings) then
    module.cleanup()
  end

  if not config then
    return module
  end

  for action, hotkey in pairs(config) do
    if action == "left" or action == "right" then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, function()
        triggerSpaceSwitch(action)
      end)
    elseif action == "index" then
      for spaceIndex = 1, math.min(hotkey.maximumSpaces or 9, 9) do
        bindings[action .. spaceIndex] = hs.hotkey.bind(hotkey.modifiers, tostring(spaceIndex), function()
          triggerSpaceSwitch(spaceIndex)
        end)
      end
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
