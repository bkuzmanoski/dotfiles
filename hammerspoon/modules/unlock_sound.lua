local module = {}

local sound = hs.sound.getByFile(hs.configdir .. "/assets/unlock.wav")

local listener

function module.init()
  if listener then
    module.cleanup()
  end

  listener = hs.distributednotifications.new(
    function()
      sound:play()
    end,
    "com.apple.screenIsUnlocked"
  ):start()

  return module
end

function module.cleanup()
  if listener then
    listener:stop()
  end

  listener = nil
end

return module
