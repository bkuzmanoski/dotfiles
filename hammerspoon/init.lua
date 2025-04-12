local modules = {}
local globalSettings = {
  numberOfSpaces = 5,
  screenTopOffset = 0,
  windowPadding = 8,
  hyperKey = { "control", "option", "shift", "command" }
}

hs.hotkey.setLogLevel("error")
hs.logger.setGlobalLogLevel("error")

require("build_binaries")()
require("create_spaces")(globalSettings.numberOfSpaces)

modules.unlockSound = require("modules/unlock_sound").init()

modules.appMenu = require("modules/app_menu").init({
  modifiers = { "cmd" },
  triggerEvent = hs.eventtap.event.types.rightMouseDown
})

modules.systemHotkeys = require("modules/system_hotkeys").init({
  focusMenuBar = { modifiers = globalSettings.hyperKey, key = "m" },
  focusDock = { modifiers = globalSettings.hyperKey, key = "b" },
  toggleLaunchpad = { modifiers = globalSettings.hyperKey, key = "l" },
  toggleMissionControl = { modifiers = globalSettings.hyperKey, key = "space" },
  toggleAppExpose = { modifiers = globalSettings.hyperKey, key = "up" },
  toggleShowDesktop = { modifiers = globalSettings.hyperKey, key = "down" },
  toggleNotificationCenter = { modifiers = globalSettings.hyperKey, key = "n" },
  goToSpaceLeft = { modifiers = globalSettings.hyperKey, key = "[" },
  goToSpaceRight = { modifiers = globalSettings.hyperKey, key = "]" },
  goToSpaceN = { modifiers = globalSettings.hyperKey },
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

modules.adjustWindowPosition = require("modules/adjust_window_position").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding
})

modules.positionAndTileWindows = require("modules/position_and_tile_windows").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  splitRatios = { 0.5, 0.33, 0.67 },
  tileTopBottomSplitRatioIndex = 2,
  hotkeys = {
    positionCenter = { modifiers = { "option", "command" }, key = "space" },
    resizeSmall = { modifiers = { "option", "command" }, key = "u" },
    resizeMedium = { modifiers = { "option", "command" }, key = "i" },
    resizeLarge = { modifiers = { "option", "command" }, key = "o" },
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

modules.moveAndResizeWindows = require("modules/move_and_resize_windows").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  snapThreshold = globalSettings.windowPadding,
  moveModifiers = { "alt", "cmd" },
  resizeModifiers = { "alt", "shift", "cmd" },
  rejectApps = { "Figma" }
})

modules.moveWindowToSpace = require("modules/move_window_to_space").init({
  modifiers = { "option", "command" },
  keys = {
    previousSpace = "left",
    nextSpace = "right"
  },
  enableNumberKeys = true,
})

modules.moveWindowToScreen = require("modules/move_window_to_screen").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  hotkeys = {
    moveOneScreenNorth = { modifiers = { "option", "command" }, key = "up" },
    moveOneScreenSouth = { modifiers = { "option", "command" }, key = "down" }
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

require("utils").playAlert(1, "Blow")
