local module = {}

local utils = require("utils")

local topOffset
local padding
local windowFilter

local function adjustWindowIfNeeded(window)
  if window:frame() == window:screen():fullFrame() then
    return
  end

  utils.adjustWindowFrame(window, topOffset, padding)
end

function module.init(config)
  if windowFilter then
    module.cleanup()
  end

  if not config then
    return module
  end

  topOffset = config.topOffset or 0
  padding = config.padding or 0
  windowFilter = hs.window.filter.new()
      :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, fullscreen = false, visible = true })
      :subscribe(hs.window.filter.windowCreated, adjustWindowIfNeeded)

  return module
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
  end

  windowFilter = nil
end

return module
