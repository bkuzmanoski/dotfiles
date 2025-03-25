local module = {}
local appProcessPairs, applicationWatcher

local function killProcess(processToKill)
  hs.execute("pkill -9 '" .. processToKill .. "'")
end

function module.killAllNow()
  if appProcessPairs and #appProcessPairs > 0 then
    for _, pair in ipairs(appProcessPairs) do
      killProcess(pair.processToKill)
    end
  end
end

function module.init(config)
  if applicationWatcher then module.cleanup() end

  if config and #config > 0 then
    appProcessPairs = config

    applicationWatcher = hs.application.watcher.new(function(_, eventType, appObject)
      if eventType == hs.application.watcher.terminated then
        local appName = appObject:name()
        for _, appProcessPair in ipairs(appProcessPairs) do
          if appName == appProcessPair.appName then
            killProcess(appProcessPair.processToKill)
          end
        end
      end
    end):start()
  end

  return module
end

function module.cleanup()
  if applicationWatcher then applicationWatcher:stop() end
  applicationWatcher = nil
end

return module
