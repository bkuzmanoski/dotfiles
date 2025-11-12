local module = {}

local utils = require("utils")

local windowFilter

function module.init(config)
  if windowFilter then
    module.cleanup()
  end

  if not config then
    return module
  end

  windowFilter = hs.window.filter.new()
      :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, fullscreen = false, visible = true })
      :subscribe(hs.window.filter.windowCreated, function(window)
        if window:frame() == window:screen():fullFrame() then return end
        utils.adjustWindowFrame(window, config.topOffset or 0, config.padding or 0)
      end)

  return module
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
  end

  windowFilter = nil
end

return module
