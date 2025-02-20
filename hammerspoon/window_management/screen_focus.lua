local module = {}

local mouseWatcher = nil
local displayWatcher = nil
local lastScreen = nil

local function focusFrontmostWindow(screen)
  -- Return early if there is only one screen
  if #hs.screen.allScreens() <= 1 then
    return
  end

  if screen then
    local windows = hs.window.orderedWindows()
    for _, window in ipairs(windows) do
      if window:screen():id() == screen:id() and window:isVisible() then
        window:focus()
        break
      end
    end
  end
end

local function checkForScreenChange()
  local currentScreen = hs.mouse.getCurrentScreen()
  if currentScreen and lastScreen and currentScreen:id() ~= lastScreen:id() then
    lastScreen = currentScreen
    focusFrontmostWindow(currentScreen)
  end
end

local function startMouseWatcher()
  if mouseWatcher then
    mouseWatcher:stop()
  end

  lastScreen = hs.mouse.getCurrentScreen()
  mouseWatcher = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
    checkForScreenChange()
    return false
  end)
  mouseWatcher:start()
end

local function stopMouseWatcher()
  if mouseWatcher then
    mouseWatcher:stop()
    mouseWatcher = nil
  end
end

-- Start/stop mouseWatcher based on number of screens
local function updateMouseWatcher()
  if #hs.screen.allScreens() > 1 then
    if not mouseWatcher then
      startMouseWatcher()
    end
  else
    stopMouseWatcher()
  end
end

function module.init()
  if not displayWatcher then
    displayWatcher = hs.screen.watcher.new(function()
      updateMouseWatcher()
    end)
    displayWatcher:start()
  end

  updateMouseWatcher()
end

function module.cleanup()
  if displayWatcher then
    displayWatcher:stop()
    displayWatcher = nil
  end

  stopMouseWatcher()
end

return module
