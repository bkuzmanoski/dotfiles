-- Initialise plugins
local sketchybar = require("sketchybar_helpers")
sketchybar.windowTitle.ignoreApps = {
  "Activity Monitor",
  "Equinox",
  "Font Book"
}
sketchybar.windowTitle.maxLength = 50
sketchybar.windowTitle.patternsToRemove = {
  " – Audio playing$",
  " - High memory usage - .*$",
  " – Camera recording$",
  " – Microphone recording$",
  " – Camera and microphone recording$"
}
sketchybar.init()

local windowManagement = require("window_management")
local primaryDisplay = "Built-in Retina Display"
local numberOfSpaces = 5
local windowPadding = 8
windowManagement.focusLeftRight.hotkeys.left = { modifiers = { "option", "command" }, key = "[" }
windowManagement.focusLeftRight.hotkeys.right = { modifiers = { "option", "command" }, key = "]" }
windowManagement.position.ignoreApps = {
  "Alcove",
  "CleanShot X",
  "Notification Centre"
}
windowManagement.position.topOffsetIgnoreDisplay = primaryDisplay
windowManagement.position.topOffset = 32
windowManagement.position.padding = windowPadding
windowManagement.moveAndResize.moveHotkeys.up = { modifiers = { "shift", "option", "command" }, key = "p" }
windowManagement.moveAndResize.moveHotkeys.down = { modifiers = { "shift", "option", "command" }, key = ";" }
windowManagement.moveAndResize.moveHotkeys.left = { modifiers = { "shift", "option", "command" }, key = "l" }
windowManagement.moveAndResize.moveHotkeys.right = { modifiers = { "shift", "option", "command" }, key = "'" }
windowManagement.moveAndResize.resizeHotkeys.up = { modifiers = { "control", "option", "command" }, key = "p" }
windowManagement.moveAndResize.resizeHotkeys.down = { modifiers = { "control", "option", "command" }, key = ";" }
windowManagement.moveAndResize.resizeHotkeys.left = { modifiers = { "control", "option", "command" }, key = "l" }
windowManagement.moveAndResize.resizeHotkeys.right = { modifiers = { "control", "option", "command" }, key = "'" }
windowManagement.moveAndResize.amount = windowPadding
windowManagement.tile.hotkeys.left = { modifiers = { "option", "command" }, key = "l" }
windowManagement.tile.hotkeys.right = { modifiers = { "option", "command" }, key = "'" }
windowManagement.tile.padding = windowPadding
windowManagement.moveToSpace.display = primaryDisplay
windowManagement.moveToSpace.numberOfSpaces = numberOfSpaces
windowManagement.moveToSpace.hotkeys = {
  modifiers = { "option", "command" },
  previousSpaceKey = "right",
  nextSpaceKey = "left"
}
windowManagement.moveToSpace.navigationHotkeyModifiers = { "ctrl" } -- Note abbreviated key label is necessary
windowManagement.init()

-- Setup hotkey: focus or open a Finder window
hs.hotkey.bind({ "control", "option", "shift", "command" }, "f", function()
  hs.application.launchOrFocus("Finder")
end)

-- Initialise spaces
local primaryScreen = hs.screen.primaryScreen()
local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)

if spacesCount < numberOfSpaces then
  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

-- Disable window adjustment animations due to buggy height adjustments when enabled
-- Note: If re-enabling animations, ensure sketchybar_helpers.offset_windows.handleWindowMove is debounced
hs.window.animationDuration = 0.0
