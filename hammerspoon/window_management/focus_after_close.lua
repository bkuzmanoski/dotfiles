local module = {}

local windowWatcher

local function focusWindowOnScreen()
  -- Brief delay to let focus update
  hs.timer.doAfter(0.1, function()
    local focusedWindow = hs.window.focusedWindow()
    local targetScreen = hs.mouse.getCurrentScreen()

    -- If the focus is already on the target screen (e.g. moved to another window of the same app), do nothing
    if focusedWindow and focusedWindow:screen() == targetScreen then
      return
    end

    local windows = hs.window.orderedWindows()
    local candidate

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
  local windowFilter = hs.window.filter.new()
  windowFilter:subscribe(hs.window.filter.windowDestroyed, focusWindowOnScreen)
  windowWatcher = windowFilter
end

function module.cleanup()
  if windowWatcher then
    windowWatcher:unsubscribeAll()
    windowWatcher = nil
  end
end

return module
