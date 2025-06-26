local module = {}
local screenWatcher, mouseTap
local lastScreen

local function startMouseTap()
  lastScreen = hs.mouse.getCurrentScreen()
  mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, function()
        local currentScreen = hs.mouse.getCurrentScreen()
        if not currentScreen or currentScreen == lastScreen then return false end

        lastScreen = currentScreen
        for _, window in ipairs(hs.window:orderedWindows()) do
          if window:screen() == currentScreen then
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
