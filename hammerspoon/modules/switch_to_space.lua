local module = {}

local utils = require("utils")

local bindings = {}

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
        utils.triggerSpaceSwitch(action)
      end)
    elseif action == "index" then
      for spaceIndex = 1, math.min(hotkey.maximumSpaces or 9, 9) do
        bindings[action .. spaceIndex] = hs.hotkey.bind(hotkey.modifiers, tostring(spaceIndex), function()
          utils.triggerSpaceSwitch(spaceIndex)
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
