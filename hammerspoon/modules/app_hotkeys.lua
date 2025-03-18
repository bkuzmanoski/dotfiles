local module = {}
local bindings = {}

function module.init(config)
  if next(bindings) then module.cleanup() end

  if config and config.modifiers and config.keys then
    for key, bundleID in pairs(config.keys) do
      bindings[bundleID] = hs.hotkey.bind(config.modifiers, key, function()
        hs.application.launchOrFocusByBundleID(bundleID)
      end)
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
