-- Initialise plugins
local sketchybar = require("sketchybar_helpers")
--sketchybar.windowTitleIgnoreApps = { "Activity Monitor", "Font Book", "Equinox" }
--sketchybar.windowTitleMaxLength = 50
--sketchybar.windowTitlePatternsToRemove = { " – Audio playing$", " - High memory usage - .*$", " – Camera recording$", " – Microphone recording$", " – Camera and microphone recording$" }
--sketchybar.windowOffsetIgnoreDisplay = "" -- Use "Built-in Retina Display" to limit to external displays only
--sketchybar.windowOffsetIgnoreApps = { "Alcove" }
--sketchybar.windowOffsetStatusbarOffset = 32
--sketchybar.windowOffsetPadding = 8

local windowManagement = require("window_management")
-- windowManagement.focusLeftRightHotkeys.left = { modifiers = { "option", "command" }, key = "[" }
-- windowManagement.focusLeftRightHotkeys.right = { modifiers = { "option", "command" }, key = "]" }
-- windowManagement.moveHotkeys.up = { modifiers = { "shift", "option", "command" }, key = "p" }
-- windowManagement.moveHotkeys.down = { modifiers = { "shift", "option", "command" }, key = ";" }
-- windowManagement.moveHotkeys.left = { modifiers = { "shift", "option", "command" }, key = "l" }
-- windowManagement.moveHotkeys.right = { modifiers = { "shift", "option", "command" }, key = "'" }
-- windowManagement.resizeHotkeys.up = { modifiers = { "control", "option", "command" }, key = "p" }
-- windowManagement.resizeHotkeys.down = { modifiers = { "control", "option", "command" }, key = ";" }
-- windowManagement.resizeHotkeys.left = { modifiers = { "control", "option", "command" }, key = "l" }
-- windowManagement.resizeHotkeys.right = { modifiers = { "control", "option", "command" }, key = "'" }
-- windowManagement.tileGap = 8
-- windowManagement.tileHotkeys.left = { modifiers = { "option", "command" }, key = "l" }
-- windowManagement.tileHotkeys.right = { modifiers = { "option", "command" }, key = "'" }

sketchybar.init()
windowManagement.init()

-- Setup hotkeys
-- Focus or open a Finder window
hs.hotkey.bind({ "control", "option", "shift", "command" }, "f", function()
  hs.application.launchOrFocus("Finder")
end)

-- Initialise spaces
local primaryScreen = hs.screen.primaryScreen()
local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)

if spacesCount < 5 then
  for _ = spacesCount + 1, 5 do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

-- Disable window adjustment animations due to buggy height adjustments when enabled
-- Note: If re-enabling animations, ensure sketchybar_helpers.offset_windows.handleWindowMove is debounced
hs.window.animationDuration = 0.0
