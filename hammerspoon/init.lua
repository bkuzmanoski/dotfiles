local numberOfSpaces = 5
local windowTopOffset = 33
local windowPadding = 8
local hyperKey = { "control", "option", "command" }
local hyperKey2 = { "control", "option", "command", "shift" }

local primaryScreen = hs.screen.primaryScreen()
local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)
if spacesCount < numberOfSpaces then
  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

local appHotkeys = require("app_hotkeys")
appHotkeys.modifiers = hyperKey
appHotkeys.keys = {
  ["c"] = "Google Chrome",
  ["d"] = "Figma",
  ["f"] = "Finder",
  ["s"] = "System Settings",
  ["t"] = "Ghostty",
  ["v"] = "Visual Studio Code",
}
appHotkeys.init()

local systemHotkeys = require("system_hotkeys")
systemHotkeys.hotkeys = {
  focusDock = { modifiers = hyperKey2, key = "d" },
  focusMenuBar = { modifiers = hyperKey2, key = "m" },
  toggleControlCenter = { modifiers = hyperKey2, key = "c" },
  toggleNotificationCenter = { modifiers = hyperKey2, key = "n" },
  applicationWindows = { modifiers = hyperKey, key = "up" },
  showDesktop = { modifiers = hyperKey, key = "down" },
  moveSpaceLeft = { modifiers = hyperKey, key = "[" },
  moveSpaceRight = { modifiers = hyperKey, key = "]" },
  moveSpaceN = { modifiers = hyperKey, key = "N" }, -- N represents a mapping of number key to space number (handled in module)
  upKeystroke = { modifiers = hyperKey, key = "p", keyRepeat = true },
  downKeystroke = { modifiers = hyperKey, key = ";", keyRepeat = true },
  leftKeystroke = { modifiers = hyperKey, key = "l", keyRepeat = true },
  rightKeystroke = { modifiers = hyperKey, key = "'", keyRepeat = true }
}
systemHotkeys.init()

local showAllSpaces = require("show_all_spaces")
showAllSpaces.hotkey = { modifiers = hyperKey, key = "space" }
showAllSpaces.init()

local toggleDarkMode = require("toggle_dark_mode")
toggleDarkMode.hotkey = { modifiers = hyperKey, key = "a" }
toggleDarkMode.init()

local pasteAsPlaintext = require("paste_as_plaintext")
pasteAsPlaintext.hotkey = { modifiers = { "option" }, key = "v" }
pasteAsPlaintext.init()

local openURLs = require("open_urls")
openURLs.hotkey = { modifiers = { "shift", "command" }, key = "o" }
openURLs.init()

local adjustPosition = require("adjust_position")
adjustPosition.topOffset = windowTopOffset
adjustPosition.padding = windowPadding
adjustPosition.init()

local positionAndTile = require("position_and_tile")
positionAndTile.topOffset = windowTopOffset
positionAndTile.padding = windowPadding
positionAndTile.hotkeys = {
  positionCenter = { modifiers = { "option", "command" }, key = "space" },
  positionReasonableSize = { modifiers = { "option", "command" }, key = "u" },
  positionAlmostMaximize = { modifiers = { "option", "command" }, key = "i" },
  positionMaximize = { modifiers = { "option", "command" }, key = "o" },
  tileLeft = { modifiers = { "option", "shift", "command" }, key = "l" },
  tileRight = { modifiers = { "option", "shift", "command" }, key = "'" },
  tileLeftAndRight = { modifiers = { "option", "command" }, key = "l" },
  tileRightAndLeft = { modifiers = { "option", "command" }, key = "'" },
  tileTopRight = { modifiers = { "option", "shift", "command" }, key = "p" },
  tileBottomRight = { modifiers = { "option", "shift", "command" }, key = ";" },
  tileTopAndBottomRight = { modifiers = { "option", "command" }, key = "p" },
  tileBottomAndTopRight = { modifiers = { "option", "command" }, key = ";" }
}
positionAndTile.init()

local moveAndResize = require("move_and_resize")
moveAndResize.modifiers = {
  move = { "alt", "cmd" },
  resize = { "alt", "shift", "cmd" }
}
moveAndResize.init()

local moveToSpace = require("move_to_space")
moveToSpace.numberOfSpaces = numberOfSpaces
moveToSpace.hotkeys = {
  modifiers = { "option", "command" },
  previousSpaceKey = "right",
  nextSpaceKey = "left"
}
moveToSpace.init()

local moveToScreen = require("move_to_screen")
moveToScreen.topOffset = windowTopOffset
moveToScreen.padding = windowPadding
moveToScreen.hotkeys = {
  up = { modifiers = { "option", "command" }, key = "up" },
  down = { modifiers = { "option", "command" }, key = "down" }
}
moveToScreen.init()

local switchWindow = require("switch_window")
switchWindow.hotkeys = {
  focusFrontmost = { modifiers = { "option", "command" }, key = "return" },
  hints = { modifiers = { "option", "command" }, key = "\\" },
  left = { modifiers = { "option", "command" }, key = "[" },
  right = { modifiers = { "option", "command" }, key = "]" }
}
switchWindow.init()

local focusAfterClose = require("focus_after_close")
focusAfterClose.init()

local focusScreen = require("focus_screen")
focusScreen.init()

hs.shutdownCallback = function()
  appHotkeys.cleanup()
  systemHotkeys.cleanup()
  showAllSpaces.cleanup()
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
