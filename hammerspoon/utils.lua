local module = {}

function module.playAlert()
  local alertSound = hs.sound.getByFile("/System/Library/Sounds/Tink.aiff") -- a.k.a. "Boop"
  if alertSound then
    alertSound:play()
  end
end

return module
