local module = {}
local screenWatcher, mouseTap
local lastScreen

local function focusFrontmostWindow(screen)
  local windows = hs.window.orderedWindows()
  if not windows or #windows == 0 then return end

  local windowsOnScreen = hs.fnutils.ifilter(windows, function(window)
    local frame = window:frame()
    return
        window:screen() == screen and
        not window:isFullscreen() and
        window:subrole() == "AXStandardWindow" and
        frame.w > 100 and
        frame.h > 100
  end)
  if #windowsOnScreen == 0 then return end

  windowsOnScreen[1]:focus()
end

local function checkForScreenChange()
  local currentScreen = hs.mouse.getCurrentScreen()

  if not lastScreen then
    lastScreen = currentScreen
    return
  end

  if currentScreen and currentScreen ~= lastScreen then
    lastScreen = currentScreen
    focusFrontmostWindow(currentScreen)
  end
end

local function updateMouseTapState()
  if #hs.screen.allScreens() > 1 then
    if not mouseTap:isEnabled() then mouseTap:start() end
    return
  end

  if mouseTap:isEnabled() then mouseTap:stop() end
end

function module.init()
  screenWatcher = hs.screen.watcher.new(updateMouseTapState):start()
  mouseTap      = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
    checkForScreenChange()
    return false
  end) -- Don't start yet

  updateMouseTapState()
end

function module.cleanup()
  if screenWatcher then screenWatcher:stop() end
  screenWatcher = nil

  if mouseTap then mouseTap:stop() end
  mouseTap = nil
end

return module
