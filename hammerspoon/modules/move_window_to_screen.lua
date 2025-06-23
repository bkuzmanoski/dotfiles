local utils = require("utils")

local module = {}
local bindings = {}
local topOffset, padding

function module.init(config)
  if next(bindings) then module.cleanup() end

  if config and config.hotkeys then
    local windowObject = hs.window.desktop()
    for action, hotkey in pairs(config.hotkeys) do
      if hotkey.modifiers and hotkey.key and windowObject[action] then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, function()
          local window = hs.window.focusedWindow()
          if not window:isStandard() or window:isFullscreen() then return end

          window[action](window, true)
          hs.timer.doAfter(hs.window.animationDuration, function()
            utils.adjustWindowFrame(window, topOffset, padding)
          end)
        end)
      end
    end

    if next(bindings) then
      topOffset = config.topOffset or 0
      padding = config.padding or 0
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
