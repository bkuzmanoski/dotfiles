local utils = require("utils")
local module = {}
local binding

local function pasteAsPlaintext()
  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focusedElement then
    utils.playAlert()
    return
  end

  local plaintext = hs.pasteboard.readString()
  if not plaintext or plaintext == "" then
    utils.playAlert()
    return
  end

  focusedElement:setAttributeValue("AXSelectedText", plaintext)
end

function module.init(config)
  if binding then module.cleanup() end

  if config.modifiers and config.key then
    binding = hs.hotkey.bind(config.modifiers, config.key, pasteAsPlaintext)
  end

  return module
end

function module.cleanup()
  if binding then
    binding:delete()
    binding = nil
  end
end

return module
