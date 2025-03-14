local module = {}
local bindings = {}

module.modifiers = {}
module.keys = {}

function module.init()
  if module.modifiers == nil then
    return
  end
  for key, bundleID in pairs(module.keys) do
    bindings[bundleID] = hs.hotkey.bind(module.modifiers, key, function()
      hs.application.launchOrFocusByBundleID(bundleID)
    end)
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
