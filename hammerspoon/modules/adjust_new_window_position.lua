local utils = require("utils")

local module = {}
local windowSubscription

function module.init(config)
  if windowSubscription then module.cleanup() end

  if not config then return module end

  windowSubscription = hs.window.filter.new()
      :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, currentSpace = true, fullscreen = false, visible = true })
      :subscribe(hs.window.filter.windowCreated, function(window)
        utils.adjustWindowFrame(window, config.topOffset or 0, config.padding or 0)
      end)

  return module
end

function module.cleanup()
  if windowSubscription then windowSubscription:unsubscribeAll() end
  windowSubscription = nil
end

return module
