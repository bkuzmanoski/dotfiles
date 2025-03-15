local utils = require("utils")
local module = {}
local binding

module.hotkey = {}

local function pasteAsPlaintext()
  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focusedElement then
    utils.playAlert()
    return
  end

  local plaintext = hs.pasteboard.readString()
  if not plaintext or plaintext == "" then
    utils.playAlert()
  end

  focusedElement:setAttributeValue("AXSelectedText", plaintext)
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
