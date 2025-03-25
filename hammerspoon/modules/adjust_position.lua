local utils = require("utils")
local module = {}
local topOffset, padding, windowSubscription

local function handleWindowEvent(window)
  if not window or window:title() == "" then return end

  local windowFrame = window:frame()
  local adjustedScreenFrame = utils.getAdjustedScreenFrame(window:screen():fullFrame(), topOffset, padding)
  local adjustedWindowFrame = utils.getAdjustedWindowFrame(adjustedScreenFrame, windowFrame)
  if windowFrame.x ~= adjustedWindowFrame.x or windowFrame.y ~= adjustedWindowFrame.y then
    window:setFrame(adjustedWindowFrame, 0)
  end
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
