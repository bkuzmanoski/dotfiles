hs.logger.setGlobalLogLevel("warning")
hs.hotkey.setLogLevel("warning")

local numberOfSpaces = 5
local windowTopOffset = 33
local windowPadding = 8
local hyper = { "control", "option", "command" }
local hyperShift = { "control", "option", "command", "shift" }

require("helpers/build_binaries")

local primaryScreen = hs.screen.primaryScreen()
local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)
if spacesCount < numberOfSpaces then
  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

local appMenu = require("app_menu")
appMenu.modifiers = { "cmd" }
appMenu.init()

local appHotkeys = require("app_hotkeys")
appHotkeys.modifiers = hyper
appHotkeys.keys = {
  ["c"] = "com.google.Chrome",
  ["d"] = "com.figma.Desktop",
  ["f"] = "com.apple.finder",
  ["s"] = "com.apple.systempreferences",
  ["t"] = "com.mitchellh.ghostty",
  ["v"] = "com.microsoft.VSCode",
}
appHotkeys.init()

local systemHotkeys = require("system_hotkeys")
systemHotkeys.hotkeys = {
  focusDock = { modifiers = hyperShift, key = "d" },
  focusMenuBar = { modifiers = hyper, key = "m" },
  toggleControlCenter = { modifiers = hyperShift, key = "c" },
  toggleNotificationCenter = { modifiers = hyper, key = "n" },
  applicationWindows = { modifiers = hyper, key = "up" },
  showDesktop = { modifiers = hyper, key = "down" },
  moveSpaceLeft = { modifiers = hyper, key = "[" },
  moveSpaceRight = { modifiers = hyper, key = "]" },
  moveSpaceN = { modifiers = hyper, key = "N" }, -- N represents a mapping of number key to space number (handled in module)
}
systemHotkeys.init()

local showAllSpaces = require("show_all_spaces")
showAllSpaces.hotkey = { modifiers = hyper, key = "space" }
showAllSpaces.init()

local toggleDarkMode = require("toggle_dark_mode")
toggleDarkMode.hotkey = { modifiers = hyper, key = "a" }
toggleDarkMode.init()

local pasteAsPlaintext = require("paste_as_plaintext")
pasteAsPlaintext.hotkey = { modifiers = { "option" }, key = "v" }
pasteAsPlaintext.init()

local reorderLines = require("reorder_lines")
reorderLines.hotkeys = {
  moveLinesUp = { modifiers = { "option" }, key = "up" },
  moveLinesDown = { modifiers = { "option" }, key = "down" }
}
reorderLines.allowApps = { "Scratchpad", "TextEdit" }
reorderLines.init()

local openTabsFromSelection = require("open_tabs_from_selection")
openTabsFromSelection.hotkey.urls = { modifiers = { "option", "shift" }, key = "o" }
openTabsFromSelection.hotkey.search = { modifiers = { "shift", "command" }, key = "o" }
openTabsFromSelection.init()

local adjustPosition = require("adjust_position")
adjustPosition.topOffset = windowTopOffset
adjustPosition.padding = windowPadding
adjustPosition.ignoreApps = { "CleanShot X" }
adjustPosition.init()

local positionAndTile = require("position_and_tile")
positionAndTile.topOffset = windowTopOffset
positionAndTile.padding = windowPadding
positionAndTile.hotkeys = {
  positionCenter = { modifiers = { "option", "command" }, key = "space" },
  positionReasonableSize = { modifiers = { "option", "command" }, key = "u" },
  positionAlmostMaximize = { modifiers = { "option", "command" }, key = "i" },
  positionMaximize = { modifiers = { "option", "command" }, key = "o" },
  tileLeft = { modifiers = { "option", "command" }, key = "l" },
  tileRight = { modifiers = { "option", "command" }, key = "'" },
  tileLeftAndRight = { modifiers = { "option", "shift", "command" }, key = "l" },
  tileRightAndLeft = { modifiers = { "option", "shift", "command" }, key = "'" },
  tileTopRight = { modifiers = { "option", "command" }, key = "p" },
  tileBottomRight = { modifiers = { "option", "command" }, key = ";" },
  tileTopAndBottomRight = { modifiers = { "option", "shift", "command" }, key = "p" },
  tileBottomAndTopRight = { modifiers = { "option", "shift", "command" }, key = ";" }
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

local focusScreen = require("focus_screen")
focusScreen.init()

hs.shutdownCallback = function()
  appMenu.cleanup()
  appHotkeys.cleanup()
  systemHotkeys.cleanup()
  showAllSpaces.cleanup()
  toggleDarkMode.cleanup()
  pasteAsPlaintext.cleanup()
  reorderLines.cleanup()
  openTabsFromSelection.cleanup()
  adjustPosition.cleanup()
  positionAndTile.cleanup()
  moveAndResize.cleanup()
  moveToSpace.cleanup()
  moveToScreen.cleanup()
  switchWindow.cleanup()
  focusScreen.cleanup()
end
