local utils = require("utils")
local module = {}
local windowSubscription

module.topOffset = 0
module.padding = 0

local function handleWindowEvent(window)
  if not window or window:title() == "" then
    return
  end

  local screenFrame = window:screen():fullFrame()
  local windowFrame = window:frame()
  local adjustedWindowFrame = utils.getAdjustedWindowFrame(screenFrame, windowFrame, module.topOffset, module.padding)
  if windowFrame.x ~= adjustedWindowFrame.x or windowFrame.y ~= adjustedWindowFrame.y then
    window:setFrame(adjustedWindowFrame, 0)
  end
end

function module.init()
  windowSubscription = hs.window.filter.new()
      :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, fullscreen = false, visible = true })
      :subscribe(hs.window.filter.windowCreated, handleWindowEvent)
end

function module.cleanup()
  if windowSubscription then
    windowSubscription:unsubscribeAll()
    windowSubscription = nil
  end
end

return module
