local module = {}

module.ignoreDisplay = ""
module.ignoreApps = {
  "Alcove",
  "CleanShot X",
  "Notification Centre"
}
module.statusbarOffset = 32
module.padding = 8

local windowFilter = nil

local function handleWindowMove(window)
  -- Get screen details and return early if it is the primary screen (with notch)
  local screen = window:screen()
  if screen:name() == module.ignoreDisplay then
    return
  end

  local appName = window:application():name()
  for _, ignoredApp in ipairs(module.ignoreApps) do
    if appName == ignoredApp then
      return
    end
  end

  -- Check if window overlaps in the menu bar area
  local screenFrame = screen:fullFrame()
  local windowFrame = window:frame()
  local originalWindowFrame = windowFrame:copy()

  -- Top edge protection
  local distanceFromTop = windowFrame.y - screenFrame.y
  if distanceFromTop < (module.statusbarOffset + module.padding) then
    windowFrame.y = screenFrame.y + module.statusbarOffset + module.padding

    local distanceFromBottom = (screenFrame.y + screenFrame.h) - (windowFrame.y + windowFrame.h)
    if distanceFromBottom < module.padding then
      -- Adjust window height if it is too close to the screen bottom after adjustment
      windowFrame.h = screenFrame.h - module.statusbarOffset - (module.padding * 2)
    end
  end

  -- Left edge protection
  local distanceFromLeft = windowFrame.x - screenFrame.x
  if distanceFromLeft < module.padding then
    windowFrame.x = screenFrame.x + module.padding

    local distanceFromRight = (screenFrame.x + screenFrame.w) - (windowFrame.x + windowFrame.w)
    if distanceFromRight < module.padding then
      -- Adjust window width if it is too close to the screen right after adjustment
      windowFrame.w = screenFrame.w - (module.padding * 2)
    end
  end

  -- Set window frame if there are adjustments
  if windowFrame.x ~= originalWindowFrame.x or
      windowFrame.y ~= originalWindowFrame.y then
    window:setFrame(windowFrame)
  end
end

function module.init()
  -- Subscribe to window move events
  windowFilter = hs.window.filter.new()
  windowFilter:subscribe(hs.window.filter.windowCreated, handleWindowMove)
  windowFilter:subscribe(hs.window.filter.windowMoved, handleWindowMove)
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
    windowFilter = nil
  end
end

return module
