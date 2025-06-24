local module = {}
local screenWatcher, windowFilter, mouseTap
local lastScreen

local function startMouseTap()
  lastScreen = hs.mouse.getCurrentScreen()
  windowFilter = hs.window.filter.new()
      :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, currentSpace = true, visible = true })
  mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
        local currentScreen = hs.mouse.getCurrentScreen()
        if not currentScreen or currentScreen == lastScreen then return false end

        lastScreen = currentScreen
        for _, window in ipairs(windowFilter:getWindows()) do
          if window:screen() == currentScreen and window:isVisible() then
            window:focus()
            return
          end
        end

        return false
      end)
      :start()
end

local function stopMouseTap()
  if mouseTap then mouseTap:stop() end
  mouseTap = nil
  windowFilter = nil
end

local function updateMouseTap()
  if #hs.screen.allScreens() <= 1 then
    stopMouseTap()
  else
    startMouseTap()
  end
end

function module.init()
  screenWatcher = hs.screen.watcher.new(updateMouseTap):start()
  updateMouseTap()
end

function module.cleanup()
  if screenWatcher then screenWatcher:stop() end
  screenWatcher = nil
  stopMouseTap()
end

return module
