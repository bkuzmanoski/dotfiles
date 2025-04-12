local utils = require("utils")

local module = {}
local windowSubscription
local topOffset, padding

local function handleWindowEvent(window)
  utils.adjustWindowFrame(window, topOffset, padding)
end

function module.init(config)
  if windowSubscription then module.cleanup() end

  if config then
    topOffset = config.topOffset or 0
    padding = config.padding or 0

    windowSubscription = hs.window.filter.new()
        :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, fullscreen = false, visible = true })
        :subscribe(hs.window.filter.windowCreated, handleWindowEvent)
  end

  return module
end

function module.cleanup()
  if windowSubscription then windowSubscription:unsubscribeAll() end
  windowSubscription = nil
end

return module
