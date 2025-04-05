local module = {}
local listener, sound

function module.init(config)
  if listener then module.cleanup() end

  if config and config.soundPath then
    sound = hs.sound.getByFile(config.soundPath)
    listener = hs.distributednotifications.new(function() sound:play() end, "com.apple.screenIsUnlocked"):start()
  end

  return module
end

function module.cleanup()
  if listener then listener:stop() end
  listener = nil
  sound = nil
end

return module
