local module = {}
local bindings = {}

function module.init(config)
  if next(bindings) then module.cleanup() end

  if config then
    local keyMap = {
      launchpad = {},
      focusDock = { modifiers = { "fn", "ctrl" }, key = "f3" },
      focusMenuBar = { modifiers = { "fn", "ctrl" }, key = "f2" },
      toggleControlCenter = { modifiers = { "fn" }, key = "c" },
      toggleNotificationCenter = { modifiers = { "fn" }, key = "n" },
      appWindows = { modifiers = { "fn", "ctrl" }, key = "down" },
      showDesktop = { modifiers = { "fn" }, key = "f11" },
      moveSpaceLeft = { modifiers = { "fn", "ctrl" }, key = "left" },
      moveSpaceRight = { modifiers = { "fn", "ctrl" }, key = "right" },
      moveSpaceN = { modifiers = { "ctrl" } }
    }
    for action, hotkey in pairs(config) do
      if keyMap[action] then
        if action == "launchpad" then
          bindings[action] = hs.hotkey.bind(
            hotkey.modifiers,
            hotkey.key,
            function() hs.execute("open /System/Applications/Launchpad.app") end)
        elseif action == "moveSpaceN" then
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

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
