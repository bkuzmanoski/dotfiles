local utils = require("utils")

local module = {}
local bindings = {}
local topOffset, padding

function module.init(config)
  if next(bindings) then module.cleanup() end

  if not config or not config.hotkeys then return module end

  for action, hotkey in pairs(config.hotkeys) do
    if hotkey.modifiers and hotkey.key then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, function()
        local window = hs.window.focusedWindow()
        if window:isFullscreen() then return end

        window[action](window, true)
        utils.adjustWindowFrame(window, topOffset, padding)
      end)
    end
  end

  if next(bindings) then
    topOffset = config.topOffset or 0
    padding = config.padding or 0
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
