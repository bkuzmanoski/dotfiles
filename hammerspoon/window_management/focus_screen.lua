local module = {}

local mouseTap, displayWatcher, lastScreen

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

local function startMouseTap()
  if mouseTap then
    mouseTap:stop()
  end

  lastScreen = hs.mouse.getCurrentScreen()
  mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
    checkForScreenChange()
    return false
  end)
  mouseTap:start()
end

local function stopMouseTap()
  if mouseTap then
    mouseTap:stop()
    mouseTap = nil
  end
end

-- Run mouseTap based on number of screens
local function updateMouseTap()
  if #hs.screen.allScreens() > 1 then
    if not mouseTap then
      startMouseTap()
    end
  else
    stopMouseTap()
  end
end

function module.init()
  if not displayWatcher then
    displayWatcher = hs.screen.watcher.new(function()
      updateMouseTap()
    end)
    displayWatcher:start()
  end

  updateMouseTap()
end

function module.cleanup()
  if displayWatcher then
    displayWatcher:stop()
    displayWatcher = nil
  end

  stopMouseTap()
end

return module
