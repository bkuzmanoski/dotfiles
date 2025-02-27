local primaryDisplay = "Built-in Retina Display"
local numberOfSpaces = 5
local windowPadding = 8

-- require("hs.ipc")

-- Initialise spaces
local primaryScreen = hs.screen.primaryScreen()
local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)

if spacesCount < numberOfSpaces then
  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

-- Show MenuWhere menu when the current app icon is clicked
-- local appMenu = require("app_menu")
-- appMenu.targetArea = { x = 16, y = 8, w = 23, h = 23 }
-- appMenu.rightClickModifiers = { "cmd" }
-- appMenu.init()

-- Move focus to the window to the left or right of the focused window
local focusLeftRight = require("focus_left_right")
focusLeftRight.hotkeys.left = { modifiers = { "option", "command" }, key = "[" }
focusLeftRight.hotkeys.right = { modifiers = { "option", "command" }, key = "]" }
focusLeftRight.init()

-- Focus the topmost window on the screen when the mouse enters it
local focusScreen = require("focus_screen")
focusScreen.init()

-- Move and resize window
local moveAndResize = require("move_and_resize")
moveAndResize.moveHotkeys.up = { modifiers = { "shift", "option", "command" }, key = "p" }
moveAndResize.moveHotkeys.down = { modifiers = { "shift", "option", "command" }, key = ";" }
moveAndResize.moveHotkeys.left = { modifiers = { "shift", "option", "command" }, key = "l" }
moveAndResize.moveHotkeys.right = { modifiers = { "shift", "option", "command" }, key = "'" }
moveAndResize.resizeHotkeys.up = { modifiers = { "control", "option", "command" }, key = "p" }
moveAndResize.resizeHotkeys.down = { modifiers = { "control", "option", "command" }, key = ";" }
moveAndResize.resizeHotkeys.left = { modifiers = { "control", "option", "command" }, key = "l" }
moveAndResize.resizeHotkeys.right = { modifiers = { "control", "option", "command" }, key = "'" }
moveAndResize.amount = windowPadding
moveAndResize.init()

-- Move window to screen up/down/left/right
local moveToScreen = require("move_to_screen")
moveToScreen.hotkeys.up = { modifiers = { "option", "command" }, key = "up" }
moveToScreen.hotkeys.down = { modifiers = { "option", "command" }, key = "down" }
moveToScreen.padding = windowPadding
moveToScreen.init()

-- Move window to space 1~5
local moveToSpace = require("move_to_space")
moveToSpace.allowDisplay = primaryDisplay
moveToSpace.numberOfSpaces = numberOfSpaces
moveToSpace.hotkeys.modifiers = { "option", "command" }
moveToSpace.hotkeys.previousSpaceKey = "right"
moveToSpace.hotkeys.nextSpaceKey = "left"
moveToSpace.navigationHotkeyModifiers = { "ctrl" } -- Note: abbreviated key label is necessary
moveToSpace.init()

-- Apply window padding and maintain an offset from the top of the screen
local position = require("position")
-- position.ignoreApps = {}
-- position.topOffsetIgnoreDisplay = ""
position.topOffset = 32
position.padding = windowPadding
position.init()

-- Tile windows
local tile = require("tile")
tile.hotkeys.left = { modifiers = { "option", "command" }, key = "l" }
tile.hotkeys.right = { modifiers = { "option", "command" }, key = "'" }
tile.padding = windowPadding
tile.init()

-- Focus or open a Finder window
hs.hotkey.bind({ "control", "option", "shift", "command" }, "f", function()
  hs.application.launchOrFocus("Finder")
end)

-- Show all spaces
hs.hotkey.bind({ "control", "option", "shift", "command" }, "space", function()
  local mousePosition = hs.mouse.absolutePosition()
  hs.mouse.absolutePosition({ x = 10, y = 10 })
  hs.eventtap.keyStroke({ "fn", "ctrl" }, 'up')
  hs.mouse.absolutePosition(mousePosition)
end)
