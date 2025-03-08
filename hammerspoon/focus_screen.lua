local module = {}
local displayWatcher, windowFilter, mouseTap, lastScreen

local function focusFrontmostWindow(screen)
  if screen then
    if #hs.screen.allScreens() <= 1 then
      return
    end

    local windows = windowFilter:getWindows()
    for _, window in ipairs(windows) do
      if window:screen() == screen and window:isVisible() then
        window:focus()
        break
      end
    end
  end
end

local function checkForScreenChange()
  local currentScreen = hs.mouse.getCurrentScreen()
  if currentScreen and lastScreen and currentScreen ~= lastScreen then
    lastScreen = currentScreen
    focusFrontmostWindow(currentScreen)
  end
end

local function startMouseTap()
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
  displayWatcher = hs.screen.watcher.new(updateMouseTap)
  displayWatcher:start()
  windowFilter = hs.window.filter.new()
      :setOverrideFilter({
        allowRoles = { "AXStandardWindow" },
        currentSpace = true,
        visible = true
      })
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
