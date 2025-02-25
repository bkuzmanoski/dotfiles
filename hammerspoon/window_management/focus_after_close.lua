local module = {}

local windowFilter

local function focusWindowOnScreen()
  hs.timer.doAfter(0.1, function()
    local targetScreen = hs.mouse.getCurrentScreen()
    local focusedWindow = hs.window.focusedWindow()
    if focusedWindow and
        focusedWindow:screen() == targetScreen and
        not focusedWindow:title() == "" then
      return
    end

    local candidate
    local windows = hs.window.orderedWindows()
    for _, window in ipairs(windows) do
      if window:isVisible() and window:screen() == targetScreen then
        candidate = window
        break
      end
    end

    if candidate then
      candidate:focus()
    end
  end)
end

function module.init()
  windowFilter = hs.window.filter.new()
  windowFilter:subscribe(hs.window.filter.windowDestroyed, focusWindowOnScreen)
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
    windowFilter = nil
  end
end

return module
