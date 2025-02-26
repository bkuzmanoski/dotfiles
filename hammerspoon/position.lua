local module = {}
local windowFilter

module.ignoreApps = {}
module.topOffsetIgnoreDisplay = ""
module.topOffset = 0
module.padding = 0

local function handleWindowEvent(window)
  local app = window:application()
  if not app then
    return
  end

  local screen = window:screen()
  local screenFrame = screen:fullFrame()
  local windowFrame = window:frame()
  local originalWindowFrame = windowFrame:copy()
  local topOffset = module.topOffset
  if screen:name() == module.topOffsetIgnoreDisplay then
    topOffset = 0
  end

  local distanceFromLeft = windowFrame.x - screenFrame.x
  if distanceFromLeft < (module.padding) then
    windowFrame.x = screenFrame.x + module.padding

    local distanceFromRight = (screenFrame.x + screenFrame.w) - (windowFrame.x + windowFrame.w)
    if distanceFromRight < module.padding then
      windowFrame.w = screenFrame.w - (module.padding * 2)
    end
  end

  local distanceFromTop = windowFrame.y - screenFrame.y
  if distanceFromTop < (topOffset + module.padding) then
    windowFrame.y = screenFrame.y + topOffset + module.padding

    local distanceFromBottom = (screenFrame.y + screenFrame.h) - (windowFrame.y + windowFrame.h)
    if distanceFromBottom < module.padding then
      windowFrame.h = screenFrame.h - topOffset - (module.padding * 2)
    end
  end

  if windowFrame.x ~= originalWindowFrame.x or
      windowFrame.y ~= originalWindowFrame.y then
    window:setFrame(windowFrame)
  end
end

function module.init()
  windowFilter = hs.window.filter.new()
  windowFilter:setOverrideFilter({ allowRoles = { "AXStandardWindow" }, fullscreen = false })
  for _, appName in ipairs(module.ignoreApps) do
    windowFilter:rejectApp(appName)
  end
  windowFilter:subscribe(hs.window.filter.windowCreated, handleWindowEvent)
  windowFilter:subscribe(hs.window.filter.windowMoved, handleWindowEvent)
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
    windowFilter = nil
  end
end

return module
