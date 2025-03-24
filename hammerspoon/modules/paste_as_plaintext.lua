local utils = require("utils")
local module = {}
local binding

local function pasteAsPlaintext()
  local plaintext = hs.pasteboard.readString()
  if not plaintext or plaintext == "" then
    return
  end

  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if focusedElement then
    local focusedElementRole = focusedElement:attributeValue("AXRole")
    if (focusedElementRole == "AXTextField" or focusedElementRole == "AXTextArea") then
      focusedElement:setAttributeValue("AXSelectedText", plaintext)
    end
  end
end

function module.init(config)
  if binding then module.cleanup() end

  if config.modifiers and config.key then
    binding = hs.hotkey.bind(config.modifiers, config.key, pasteAsPlaintext, nil, pasteAsPlaintext)
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
