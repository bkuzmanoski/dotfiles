-- Temporary workaround: the Dock intermittently stops handling the "Switch to Desktop N" shortcuts, which breaks
-- `move_window_to_space`. Restarting the Dock restores them. Remove once macOS fixes it.

local module = {}

local watcher

function module.init()
  if watcher then
    module.cleanup()
  end

  watcher = hs.caffeinate.watcher.new(
    function(event)
      if event == hs.caffeinate.watcher.systemDidWake then
        hs.execute("/usr/bin/killall Dock")
      end
    end
  ):start()

  return module
end

function module.cleanup()
  if watcher then
    watcher:stop()
  end

  watcher = nil
end

return module
