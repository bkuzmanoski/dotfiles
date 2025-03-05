local module = {}
local bindings = {}

module.modifiers = {}
module.keys = {}

function module.init()
  if next(module.modifiers) then
    for key, appName in pairs(module.keys) do
      bindings[appName] = hs.hotkey.bind(module.modifiers, key, function()
        hs.application.launchOrFocus(appName)
      end)
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
