local module = {}

local appProcessPairs = {}
local startupTimer
local appWatcher

local function killHelpers(targetAppName)
  hs.fnutils.each(appProcessPairs, function(pair)
    if not targetAppName or pair.appName == targetAppName then
      hs.execute("pkill -x '" .. pair.processToKill .. "' >/dev/null 2>&1")
    end
  end)
end

function module.init(config)
  if appWatcher then
    module.cleanup()
  end

  if not config or #config == 0 then
    return module
  end

  appProcessPairs = config

  startupTimer = hs.timer.doAfter(10, function()
    killHelpers()
    startupTimer = nil
  end)

  appWatcher = hs.application.watcher.new(function(_, eventType, app)
    if eventType == hs.application.watcher.terminated then
      killHelpers(app:name())
    end
  end):start()
end

function module.cleanup()
  if startupTimer then
    startupTimer:stop()
  end

  startupTimer = nil

  if appWatcher then
    appWatcher:stop()
  end

  appWatcher = nil
end

return module
