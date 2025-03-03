local primaryDisplay = "Built-in Retina Display"
local numberOfSpaces = 5
local windowTopOffset = 33 -- 32px + 1px for the top border
local windowPadding = 8

-- Initialise spaces
local primaryScreen = hs.screen.primaryScreen()
local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)

if spacesCount < numberOfSpaces then
  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

-- Apply topOffset and padding to new windows if required
local adjustPosition = require("adjust_position")
adjustPosition.topOffset = windowTopOffset
adjustPosition.padding = windowPadding
adjustPosition.init()

-- Move focus to the window to the left or right of the focused window
local focusLeftRight = require("focus_left_right")
focusLeftRight.hotkeys.left = { modifiers = { "option", "command" }, key = "[" }
focusLeftRight.hotkeys.right = { modifiers = { "option", "command" }, key = "]" }
focusLeftRight.init()

-- Focus the topmost window on the screen when the mouse enters it
local focusScreen = require("focus_screen")
focusScreen.init()

-- Move and resize windows
local moveAndResize = require("move_and_resize")
moveAndResize.moveAmount = windowPadding
moveAndResize.resizeAmount = windowPadding
moveAndResize.hotkeys.moveUp = { modifiers = { "control", "option", "command" }, key = "p" }
moveAndResize.hotkeys.moveDown = { modifiers = { "control", "option", "command" }, key = ";" }
moveAndResize.hotkeys.moveLeft = { modifiers = { "control", "option", "command" }, key = "l" }
moveAndResize.hotkeys.moveRight = { modifiers = { "control", "option", "command" }, key = "'" }
moveAndResize.hotkeys.resizeUp = { modifiers = { "option", "shift", "command" }, key = "p" }
moveAndResize.hotkeys.resizeDown = { modifiers = { "option", "shift", "command" }, key = ";" }
moveAndResize.hotkeys.resizeLeft = { modifiers = { "option", "shift", "command" }, key = "l" }
moveAndResize.hotkeys.resizeRight = { modifiers = { "option", "shift", "command" }, key = "'" }
moveAndResize.hotkeys.grow = { modifiers = { "option", "command" }, key = "=" }
moveAndResize.hotkeys.shrink = { modifiers = { "option", "command" }, key = "-" }
moveAndResize.init()

-- Move window to screen up/down
local moveToScreen = require("move_to_screen")
moveToScreen.topOffset = windowTopOffset
moveToScreen.padding = windowPadding
moveToScreen.hotkeys.up = { modifiers = { "option", "command" }, key = "up" }
moveToScreen.hotkeys.down = { modifiers = { "option", "command" }, key = "down" }
moveToScreen.init()

-- Move window to next/previous space
local moveToSpace = require("move_to_space")
moveToSpace.allowDisplay = primaryDisplay
moveToSpace.numberOfSpaces = numberOfSpaces
moveToSpace.hotkeys.modifiers = { "option", "command" }
moveToSpace.hotkeys.previousSpaceKey = "right"
moveToSpace.hotkeys.nextSpaceKey = "left"
moveToSpace.navigationHotkeyModifiers = { "ctrl" } -- Note: abbreviated key label is necessary
moveToSpace.init()

-- Position and tile windows
local positionAndTile = require("position_and_tile")
positionAndTile.topOffset = windowTopOffset
positionAndTile.padding = windowPadding
positionAndTile.hotkeys.positionCenter = { modifiers = { "option", "command" }, key = "space" }
positionAndTile.hotkeys.positionReasonableSize = { modifiers = { "option", "command" }, key = "r" }
positionAndTile.hotkeys.positionAlmostMaximize = { modifiers = { "option", "command" }, key = "n" }
positionAndTile.hotkeys.positionMaximize = { modifiers = { "option", "command" }, key = "m" }
positionAndTile.hotkeys.positionTopRight = { modifiers = { "option", "command" }, key = "t" }
positionAndTile.hotkeys.positionBottomCenter = { modifiers = { "option", "command" }, key = "b" }
positionAndTile.hotkeys.tileLeft = { modifiers = { "option", "command" }, key = "p" }
positionAndTile.hotkeys.tileRight = { modifiers = { "option", "command" }, key = ";" }
positionAndTile.hotkeys.tileLeftAndRight = { modifiers = { "option", "command" }, key = "l" }
positionAndTile.hotkeys.tileRightAndLeft = { modifiers = { "option", "command" }, key = "'" }
positionAndTile.hotkeys.tileTopRight = { modifiers = { "option", "shift", "command" }, key = "t" }
positionAndTile.hotkeys.tileBottomRight = { modifiers = { "option", "shift", "command" }, key = "b" }
positionAndTile.hotkeys.tileTopAndBottomRight = { modifiers = { "option", "command" }, key = "g" }
positionAndTile.hotkeys.tileBottomAndTopRight = { modifiers = { "option", "shift", "command" }, key = "g" }
positionAndTile.init()

-- Show all spaces
hs.hotkey.bind({ "control", "option", "shift", "command" }, "space", function()
  local mousePosition = hs.mouse.absolutePosition()
  hs.mouse.absolutePosition({ x = 10, y = 10 })
  hs.eventtap.keyStroke({ "fn", "ctrl" }, 'up')
  hs.mouse.absolutePosition(mousePosition)
end)

-- Focus or open a Finder window
hs.hotkey.bind({ "control", "option", "shift", "command" }, "f", function()
  hs.application.launchOrFocus("Finder")
end)
