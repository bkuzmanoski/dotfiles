local module = {}

module.notchDisplayName = "Built-in Retina Display"
module.statusbarOffset = 40
module.bottomPadding = 8

local windowFilter = nil

local function handleWindowMove(window)
  -- Get screen details and return early if it is the primary screen (with notch)
  local screen = window:screen()
  if screen:name() == module.notchDisplayName then
    return
  end

  -- Check if window overlaps in the menu bar area
  local screenFrame = screen:frame()
  local windowFrame = window:frame()

  local distanceFromTop = windowFrame.y - screenFrame.y
  if distanceFromTop < module.statusbarOffset then
    -- Adjust window position
    windowFrame.y = screenFrame.y + module.statusbarOffset

    -- Check if window is too close to the screen bottom after adjustment
    local distanceFromBottom = (screenFrame.y + screenFrame.h) - (windowFrame.y + windowFrame.h)
    if distanceFromBottom < module.bottomPadding then
      -- Adjust window height
      windowFrame.h = screenFrame.h - module.statusbarOffset - module.bottomPadding
    end

    -- Set adjusted window frame
    window:setFrame(windowFrame)
  end
end

function module.init()
  -- Subscribe to window move events
  windowFilter = hs.window.filter.new()
  windowFilter:subscribe(hs.window.filter.windowMoved, handleWindowMove)
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
    windowFilter = nil
  end
end

return module
