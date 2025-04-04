hs.console.level(hs.drawing.windowLevels.floating)
hs.hotkey.setLogLevel("warning")
hs.logger.setGlobalLogLevel("warning")

local modules = {}
local globalSettings = {
  numberOfSpaces = 5,
  screenTopOffset = 33,
  windowPadding = 8,
  hyperKeyPrimary = { "control", "option", "command" },
  hyperKeySecondary = { "control", "option", "command", "shift" }
}

require("build_binaries")()
require("create_spaces")(globalSettings.numberOfSpaces)

modules.appMenu = require("modules/app_menu").init({
  modifiers = { "cmd" },
  triggerEvent = hs.eventtap.event.types.rightMouseDown,
  enableUrlEvents = true
})

modules.appHotkeys = require("modules/app_hotkeys").init({
  modifiers = globalSettings.hyperKeyPrimary,
  keys = {
    ["c"] = "com.google.Chrome",
    ["d"] = "com.figma.Desktop",
    ["f"] = "com.apple.finder",
    ["s"] = "com.apple.systempreferences",
    ["t"] = "com.mitchellh.ghostty",
    ["v"] = "com.microsoft.VSCode",
  }
})

modules.systemHotkeys = require("modules/system_hotkeys").init({
  launchpad = { modifiers = globalSettings.hyperKeyPrimary, key = "l" },
  focusDock = { modifiers = globalSettings.hyperKeySecondary, key = "d" },
  focusMenuBar = { modifiers = globalSettings.hyperKeyPrimary, key = "m" },
  toggleControlCenter = { modifiers = globalSettings.hyperKeySecondary, key = "c" },
  toggleNotificationCenter = { modifiers = globalSettings.hyperKeyPrimary, key = "n" },
  appWindows = { modifiers = globalSettings.hyperKeyPrimary, key = "up" },
  showDesktop = { modifiers = globalSettings.hyperKeyPrimary, key = "down" },
  moveSpaceLeft = { modifiers = globalSettings.hyperKeyPrimary, key = "[" },
  moveSpaceRight = { modifiers = globalSettings.hyperKeyPrimary, key = "]" },
  moveSpaceN = { modifiers = globalSettings.hyperKeyPrimary },
})

modules.showAllSpaces = require("modules/show_all_spaces").init({
  modifiers = globalSettings.hyperKeyPrimary, key = "space"
})

modules.pasteAsPlaintext = require("modules/paste_as_plaintext").init({
  modifiers = { "option" }, key = "v"
})

modules.reorderLines = require("modules/reorder_lines").init({
  allowApps = { "Scratchpad", "TextEdit" },
  hotkeys = {
    moveLinesUp = { modifiers = { "option" }, key = "up" },
    moveLinesDown = { modifiers = { "option" }, key = "down" }
  }
})

modules.openTabsFromSelection = require("modules/open_tabs_from_selection").init({
  openSelectedUrls = { modifiers = { "option", "shift" }, key = "o" },
  searchForSelection = { modifiers = { "shift", "command" }, key = "o" }
})

modules.focusWindow = require("modules/focus_window").init({
  focusFrontmost = { modifiers = { "option", "command" }, key = "return" },
  focusLeft = { modifiers = { "option", "command" }, key = "[" },
  focusRight = { modifiers = { "option", "command" }, key = "]" },
})

modules.adjustPosition = require("modules/adjust_position").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding
})

modules.positionAndTile = require("modules/position_and_tile").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  splitRatios = { 0.5, 0.33, 0.67 },
  tileTopBottomSplitRatioIndex = 2,
  hotkeys = {
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
})

modules.moveAndResize = require("modules/move_and_resize").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  threshold = globalSettings.windowPadding,
  moveModifiers = { "alt", "cmd" },
  resizeModifiers = { "alt", "shift", "cmd" },
  denyApps = { "Figma" }
})

modules.moveToSpace = require("modules/move_to_space").init({
  modifiers = { "option", "command" },
  keys = {
    previousSpace = "left",
    nextSpace = "right"
  },
  enableNumberedKeys = true,
})

modules.moveToScreen = require("modules/move_to_screen").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  hotkeys = {
    toNorth = { modifiers = { "option", "command" }, key = "up" },
    toSouth = { modifiers = { "option", "command" }, key = "down" }
  }
})

modules.focusScreen = require("modules/focus_screen").init()

modules.killHelpersOnQuit = require("modules/kill_helpers_on_quit").init({
  { appName = "Figma", processToKill = "figma_agent" }
})
hs.timer.doAfter(5, modules.killHelpersOnQuit.killAllNow)

hs.shutdownCallback = function()
  for _, module in pairs(modules) do
    if type(module.cleanup) == "function" then module.cleanup() end
  end
end
