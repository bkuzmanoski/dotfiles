local module = {}
local appProcessPairs = {}
local appWatcher

function module.init(config)
  if appWatcher then module.cleanup() end

  if not config or #config == 0 then return module end

  appProcessPairs = config
  appWatcher = hs.application.watcher.new(function(_, eventType, app)
        if eventType == hs.application.watcher.terminated then
          hs.fnutils.each(appProcessPairs, function(pair)
            if app:name() == pair.appName then hs.execute("pkill '" .. pair.processToKill .. "'") end
          end)
        end
      end)
      :start()
end

function module.cleanup()
  if appWatcher then appWatcher:stop() end
  appWatcher = nil
end

return module
