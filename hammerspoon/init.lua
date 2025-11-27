local utils = require("utils")
local settings = {
  numberOfSpaces = 3,
  screenTopOffset = -8,
  windowPadding = 8,
  splitRatios = { 0.5, 0.3, 0.7 },
  hyperKey = { "control", "option", "shift", "command" }
}

local modules = {}

hs.hotkey.setLogLevel("error")
hs.logger.setGlobalLogLevel("error")
hs.window.animationDuration = 0
hs.shutdownCallback = function()
  for _, module in pairs(modules) do
    if type(module.cleanup) == "function" then module.cleanup() end
  end
end

utils.createSpaces(settings.numberOfSpaces)
hs.execute("${HOME}/.dotfiles/utils/run_command.sh FloatingMenuBar --background")
hs.execute("${HOME}/.dotfiles/utils/run_command.sh HideMenuBarItems --background")
hs.execute("${HOME}/.dotfiles/utils/run_command.sh ScrollToZoom --background")

modules.unlockSound = require("modules/unlock_sound").init()
modules.systemHotkeys = require("modules/system_hotkeys").init({
  toggleLaunchpad = { modifiers = settings.hyperKey, key = "l" },
  toggleMissionControl = { modifiers = settings.hyperKey, key = "space" },
  toggleNotificationCenter = { modifiers = settings.hyperKey, key = "n" },
  goToSpaceLeft = { modifiers = settings.hyperKey, key = "o" },
  goToSpaceRight = { modifiers = settings.hyperKey, key = "p" },
  goToSpaceN = { modifiers = settings.hyperKey }
})
modules.adjustNewWindowPosition = require("modules/adjust_new_window_position").init({
  topOffset = settings.screenTopOffset,
  padding = settings.windowPadding
})
modules.positionWindow = require("modules/position_window").init({
  topOffset = settings.screenTopOffset,
  padding = settings.windowPadding,
  splitRatios = settings.splitRatios,
  hotkeys = {
    center = { modifiers = { "option", "command" }, key = "space" },
    centerSmall = { modifiers = { "option", "command" }, key = "u" },
    centerMedium = { modifiers = { "option", "command" }, key = "i" },
    centerLarge = { modifiers = { "option", "command" }, key = "o" },
    left = { modifiers = { "option", "command" }, key = "l" },
    right = { modifiers = { "option", "command" }, key = "'" }
  }
})
modules.tileWindow = require("modules/tile_window").init({
  topOffset = settings.screenTopOffset,
  padding = settings.windowPadding,
  splitRatios = settings.splitRatios,
  initialNumberOfStackedWindows = 1,
  hotkeys = {
    tileLeft = { modifiers = { "option", "shift", "command" }, key = "l" },
    tileRight = { modifiers = { "option", "shift", "command" }, key = "'" },
    increaseStackSize = { modifiers = { "option", "shift", "command" }, key = "=" },
    decreaseStackSize = { modifiers = { "option", "shift", "command" }, key = "-" },
    promoteWindowToMain = { modifiers = { "option", "shift", "command" }, key = "return" },
    promoteWindow = { modifiers = { "option", "shift", "command" }, key = "p" },
    demoteWindow = { modifiers = { "option", "shift", "command" }, key = ";" },
    floatWindow = { modifiers = { "option", "shift", "command" }, key = "f" },
    stopTiling = { modifiers = { "option", "shift", "command" }, key = "space" }
  },
  excludeApps = { "Activity Monitor", "CleanShot X", "Console", "Ghostty", "Hammerspoon", "System Settings" }
})
modules.moveAndResizeWindow = require("modules/move_and_resize_window").init({
  topOffset = settings.screenTopOffset,
  padding = settings.windowPadding,
  snapThreshold = settings.windowPadding,
  moveModifiers = { "alt", "cmd" },
  resizeModifiers = { "alt", "shift", "cmd" },
  excludeApps = { "Figma" }
})
modules.moveWindowToSpace = require("modules/move_window_to_space").init({
  modifiers = { "option", "command" },
  keys = { previousSpace = "left", nextSpace = "right" },
  enableNumberKeys = true,
})
modules.moveWindowToScreen = require("modules/move_window_to_screen").init({
  topOffset = settings.screenTopOffset,
  padding = settings.windowPadding,
  hotkeys = {
    moveOneScreenNorth = { modifiers = { "option", "command" }, key = "up" },
    moveOneScreenSouth = { modifiers = { "option", "command" }, key = "down" }
  }
})
modules.focusWindow = require("modules/focus_window").init({
  hotkeys = {
    frontmost = { modifiers = { "option", "command" }, key = "return" },
    left = { modifiers = settings.hyperKey, key = "[" },
    right = { modifiers = settings.hyperKey, key = "]" }
  }
})
modules.focusWindowOnScreen = require("modules/focus_window_on_screen").init()
modules.killHelpersOnQuit = require("modules/kill_helpers_on_quit").init({
  { appName = "Figma", processToKill = "figma_agent" }
})

utils.playAlert(1, "Blow")
