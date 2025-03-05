local numberOfSpaces = 5
local windowPadding = 8

local primaryScreen = hs.screen.primaryScreen()
local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)
if spacesCount < numberOfSpaces then
  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

local showAllSpaces = require("show_all_spaces")
showAllSpaces.hotkey = { modifiers = { "control", "option", "shift" }, key = "space" }
showAllSpaces.init()

local appHotkeys = require("app_hotkeys")
appHotkeys.modifiers = { "control", "option", "shift" }
appHotkeys.keys = {
  ["c"] = "Google Chrome",
  ["f"] = "Finder",
  ["g"] = "Figma",
  ["s"] = "System Settings",
  ["t"] = "Ghostty",
  ["v"] = "Visual Studio Code",
}
appHotkeys.init()

local toggleDarkMode = require("toggle_dark_mode")
toggleDarkMode.hotkey = { modifiers = { "control", "option", "shift" }, key = "a" }
toggleDarkMode.init()

local pasteAsPlaintext = require("paste_as_plaintext")
pasteAsPlaintext.hotkey = { modifiers = { "option" }, key = "v" }
pasteAsPlaintext.init()

local openURLs = require("open_urls")
openURLs.hotkey = { modifiers = { "shift", "command" }, key = "o" }
openURLs.init()

local adjustPosition = require("adjust_position")
adjustPosition.padding = windowPadding
adjustPosition.init()

local positionAndTile = require("position_and_tile")
positionAndTile.padding = windowPadding
positionAndTile.hotkeys.positionCenter = { modifiers = { "option", "command" }, key = "space" }
positionAndTile.hotkeys.positionReasonableSize = { modifiers = { "option", "command" }, key = "r" }
positionAndTile.hotkeys.positionAlmostMaximize = { modifiers = { "option", "command" }, key = "n" }
positionAndTile.hotkeys.positionMaximize = { modifiers = { "option", "command" }, key = "m" }
positionAndTile.hotkeys.tileLeft = { modifiers = { "option", "command" }, key = "p" }
positionAndTile.hotkeys.tileRight = { modifiers = { "option", "command" }, key = ";" }
positionAndTile.hotkeys.tileLeftAndRight = { modifiers = { "option", "command" }, key = "l" }
positionAndTile.hotkeys.tileRightAndLeft = { modifiers = { "option", "command" }, key = "'" }
positionAndTile.hotkeys.tileTopRight = { modifiers = { "option", "shift", "command" }, key = "t" }
positionAndTile.hotkeys.tileBottomRight = { modifiers = { "option", "shift", "command" }, key = "b" }
positionAndTile.hotkeys.tileTopAndBottomRight = { modifiers = { "option", "command" }, key = "g" }
positionAndTile.hotkeys.tileBottomAndTopRight = { modifiers = { "option", "shift", "command" }, key = "g" }
positionAndTile.init()

local moveAndResize = require("move_and_resize")
moveAndResize.moveModifiers = { "alt", "cmd" }
moveAndResize.resizeModifiers = { "alt", "shift", "cmd" }
moveAndResize.init()

local moveToSpace = require("move_to_space")
moveToSpace.numberOfSpaces = numberOfSpaces
moveToSpace.hotkeys.modifiers = { "option", "command" }
moveToSpace.hotkeys.previousSpaceKey = "right"
moveToSpace.hotkeys.nextSpaceKey = "left"
moveToSpace.navigationHotkeyModifiers = { "ctrl" }
moveToSpace.init()

local moveToScreen = require("move_to_screen")
moveToScreen.padding = windowPadding
moveToScreen.hotkeys.up = { modifiers = { "option", "command" }, key = "up" }
moveToScreen.hotkeys.down = { modifiers = { "option", "command" }, key = "down" }
moveToScreen.init()

local switchWindow = require("switch_window")
switchWindow.hotkeys.left = { modifiers = { "option", "command" }, key = "[" }
switchWindow.hotkeys.right = { modifiers = { "option", "command" }, key = "]" }
-- switchWindow.hotkeys.hints = { modifiers = { "option", "command" }, key = "tab" }
switchWindow.init()

local focusAfterClose = require("focus_after_close")
focusAfterClose.init()

local focusScreen = require("focus_screen")
focusScreen.init()

hs.shutdownCallback = function()
  showAllSpaces.cleanup()
  appHotkeys.cleanup()
  toggleDarkMode.cleanup()
  pasteAsPlaintext.cleanup()
  adjustPosition.cleanup()
  positionAndTile.cleanup()
  moveAndResize.cleanup()
  moveToSpace.cleanup()
  moveToScreen.cleanup()
  switchWindow.cleanup()
  focusAfterClose.cleanup()
  focusScreen.cleanup()
end
