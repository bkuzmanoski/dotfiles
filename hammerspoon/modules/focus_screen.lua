local module = {}
local screenWatcher, windowFilter, mouseTap
local lastScreen

local function focusFrontmostWindow(screen)
  local windows = windowFilter:getWindows()
  for _, window in ipairs(windows) do
    if window:screen() == screen and window:isVisible() then
      window:focus()
      return
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
  end):start()
end

local function stopMouseTap()
  if mouseTap then mouseTap:stop() end
  mouseTap = nil
end

local function updateMouseTap()
  if #hs.screen.allScreens() <= 1 then
    if not mouseTap then stopMouseTap() end
  else
    startMouseTap()
  end
end

function module.init()
  screenWatcher = hs.screen.watcher.new(updateMouseTap):start()
  windowFilter = hs.window.filter.new()
      :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, currentSpace = true, visible = true })

  updateMouseTap()
end

function module.cleanup()
  if screenWatcher then screenWatcher:stop() end
  screenWatcher = nil

  stopMouseTap()
end

return module
