local module = {}

local windowFilter, windowSubscription

local function focusWindowOnScreen()
  local targetScreen = hs.mouse.getCurrentScreen()
  local focusedWindow = hs.window.focusedWindow()
  if focusedWindow and focusedWindow:screen() == targetScreen then
    return
  end

  local windows = windowFilter:getWindows()
  for _, window in ipairs(windows) do
    if window:screen() == targetScreen and window:isStandard() then
      window:focus()
      return
    end
  end
end

function module.init()
  windowFilter = hs.window.filter.new()
      :setOverrideFilter({
        allowRoles = { "AXStandardWindow" },
        currentSpace = true,
        fullscreen = false,
        visible = true
      })
  windowSubscription = hs.window.filter.new()
      :setOverrideFilter({
        allowRoles = { "AXStandardWindow" },
        currentSpace = true,
        fullscreen = false,
        visible = true
      })
      :subscribe(hs.window.filter.windowDestroyed, focusWindowOnScreen)
end

function module.cleanup()
  if windowSubscription then
    windowSubscription:unsubscribeAll()
    windowSubscription = nil
  end
end

return module
