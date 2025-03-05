local module = {}
local binding

module.hotkey = {}

local function pasteAsPlaintext()
  local originalData = hs.pasteboard.readAllData()
  local plaintext = hs.pasteboard.readString()
  hs.pasteboard.setContents(plaintext)
  hs.timer.usleep(100000)
  hs.eventtap.keyStroke({ "cmd" }, "v")
  hs.timer.usleep(100000)
  hs.pasteboard.writeAllData(originalData)
end

function module.init()
  if next(module.hotkey) then
    binding = hs.hotkey.bind(module.hotkey.modifiers, module.hotkey.key, pasteAsPlaintext)
  end
end

function module.cleanup()
  if binding then
    binding:delete()
    binding = nil
  end
end

return module
