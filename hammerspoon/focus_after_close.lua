local module = {}

local windowFilter

local function focusWindowOnScreen()
  local targetScreen = hs.mouse.getCurrentScreen()
  local focusedWindow = hs.window.focusedWindow()
  if focusedWindow and focusedWindow:screen() == targetScreen then
    return
  end

  local windows = hs.window.filter.new():setOverrideFilter({
    allowRoles = { "AXStandardWindow" },
    fullscreen = false,
    visible = true
  }):getWindows()
  for _, window in ipairs(windows) do
    if window:screen() == targetScreen and window:isStandard() then
      window:focus()
      return
    end
  end
end

function module.init()
  windowFilter = hs.window.filter.new():setOverrideFilter({
    allowRoles = { "AXStandardWindow" },
    currentSpace = true,
    fullscreen = false,
    visible = true
  }):subscribe(hs.window.filter.windowDestroyed, focusWindowOnScreen)
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
    windowFilter = nil
  end
end

return module
