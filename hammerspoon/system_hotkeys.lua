local module = {}
local keyMap = {
  focusDock = { modifiers = { "fn", "ctrl" }, key = "f3" },
  focusMenuBar = { modifiers = { "fn", "ctrl" }, key = "f2" },
  toggleControlCenter = { modifiers = { "fn" }, key = "c" },
  toggleNotificationCenter = { modifiers = { "fn" }, key = "n" },
  applicationWindows = { modifiers = { "fn", "ctrl" }, key = "down" },
  showDesktop = { modifiers = { "fn" }, key = "f11" },
  moveSpaceLeft = { modifiers = { "fn", "ctrl" }, key = "left" },
  moveSpaceRight = { modifiers = { "fn", "ctrl" }, key = "right" },
  moveSpaceN = { modifiers = { "ctrl" } }
}
local bindings = {}

module.hotkeys = {}

function module.init()
  for action, hotkey in pairs(module.hotkeys) do
    if keyMap[action] then
      if action == "moveSpaceN" then
        for i = 1, 9 do
          bindings[action .. i] = hs.hotkey.bind(
            hotkey.modifiers,
            tostring(i),
            function() hs.eventtap.keyStroke(keyMap[action].modifiers, tostring(i), 0) end)
        end
      else
        bindings[action] = hs.hotkey.bind(
          hotkey.modifiers,
          hotkey.key,
          function() hs.eventtap.keyStroke(keyMap[action].modifiers, keyMap[action].key) end)
      end
    end
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
