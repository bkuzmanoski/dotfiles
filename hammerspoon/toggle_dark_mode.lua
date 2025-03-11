local module = {}
local binding

module.hotkey = {}

local function toggleDarkMode()
  hs.osascript.applescript([[
    tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
  ]])
end

function module.init()
  if next(module.hotkey) then
    binding = hs.hotkey.bind(module.hotkey.modifiers, module.hotkey.key, toggleDarkMode)
  end
end

function module.cleanup()
  if binding then
    binding:delete()
    binding = nil
  end
end

return module
