local utils = require("utils")
local module = {}
local windowFilter

module.topOffset = 0
module.padding = 0

local function handleWindowEvent(window)
  if not window then
    return
  end

  local screenFrame = window:screen():fullFrame()
  local windowFrame = window:frame()
  local adjustedWindowFrame = utils.adjustWindowPosition(screenFrame, windowFrame, module.topOffset, module.padding)
  if windowFrame.x ~= adjustedWindowFrame.x or
      windowFrame.y ~= adjustedWindowFrame.y then
    window:setFrame(adjustedWindowFrame, 0)
  end
end

function module.init()
  windowFilter = hs.window.filter.new()
      :setOverrideFilter({ allowRoles = "AXStandardWindow", fullscreen = false, visible = true })
      :subscribe(hs.window.filter.windowCreated, handleWindowEvent)
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
    windowFilter = nil
  end
end

return module
