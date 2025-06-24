local modules = {}
local globalSettings = {
  numberOfSpaces = 5,
  screenTopOffset = 0,
  windowPadding = 8,
  splitRatios = { 0.5, 0.33, 0.67 },
  hyperKey = { "control", "option", "shift", "command" }
}

hs.hotkey.setLogLevel("error")
hs.logger.setGlobalLogLevel("error")

hs.window.animationDuration = 0

require("create_spaces")(globalSettings.numberOfSpaces)

hs.execute("${HOME}/.dotfiles/utils/run_command.sh HideMenuBarItems --background")
hs.execute("${HOME}/.dotfiles/utils/run_command.sh ScrollToZoom --background")

modules.unlockSound = require("modules/unlock_sound").init()

modules.systemHotkeys = require("modules/system_hotkeys").init({
  toggleLaunchpad = { modifiers = globalSettings.hyperKey, key = "l" },
  toggleMissionControl = { modifiers = globalSettings.hyperKey, key = "space" },
  toggleNotificationCenter = { modifiers = globalSettings.hyperKey, key = "n" },
  goToSpaceLeft = { modifiers = globalSettings.hyperKey, key = "[" },
  goToSpaceRight = { modifiers = globalSettings.hyperKey, key = "]" },
  goToSpaceN = { modifiers = globalSettings.hyperKey }
})

modules.adjustNewWindowPosition = require("modules/adjust_new_window_position").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding
})

modules.positionWindow = require("modules/position_window").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  splitRatios = globalSettings.splitRatios,
  hotkeys = {
    center = { modifiers = { "option", "command" }, key = "space" },
    centerSmall = { modifiers = { "option", "command" }, key = "u" },
    centerMedium = { modifiers = { "option", "command" }, key = "i" },
    centerLarge = { modifiers = { "option", "command" }, key = "o" },
    left = { modifiers = { "option", "command" }, key = "l" },
    right = { modifiers = { "option", "command" }, key = "'" }
  }
})

modules.tileWindows = require("modules/tile_windows").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  splitRatios = globalSettings.splitRatios,
  initialNumberOfStackedWindows = 1,
  hotkeys = {
    tileLeft = { modifiers = { "option", "shift", "command" }, key = "l" },
    tileRight = { modifiers = { "option", "shift", "command" }, key = "'" },
    increaseStackSize = { modifiers = { "option", "shift", "command" }, key = "=" },
    decreaseStackSize = { modifiers = { "option", "shift", "command" }, key = "-" },
    promoteWindowToMain = { modifiers = { "option", "shift", "command" }, key = "return" },
    promoteWindow = { modifiers = { "option", "shift", "command" }, key = "p" },
    demoteWindow = { modifiers = { "option", "shift", "command" }, key = ";" },
    stopTiling = { modifiers = { "option", "shift", "command" }, key = "space" }
  }
})

modules.moveAndResizeWindow = require("modules/move_and_resize_window").init({
  topOffset = globalSettings.screenTopOffset,
  padding = globalSettings.windowPadding,
  snapThreshold = globalSettings.windowPadding,
  moveModifiers = { "alt", "cmd" },
  resizeModifiers = { "alt", "shift", "cmd" },
  excludeApps = { "Figma" }
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

modules.focusWindow = require("modules/focus_window").init({
  hotkeys = {
    frontmost = { modifiers = { "option", "command" }, key = "return" },
    left = { modifiers = { "option", "command" }, key = "[" },
    right = { modifiers = { "option", "command" }, key = "]" }
  }
})

modules.focusWindowOnScreenEnter = require("modules/focus_window_on_screen_enter").init()

modules.killHelpersOnQuit = require("modules/kill_helpers_on_quit").init({
  { appName = "Figma", processToKill = "figma_agent" }
})

hs.shutdownCallback = function()
  for _, module in pairs(modules) do
    if type(module.cleanup) == "function" then module.cleanup() end
  end
end

require("utils").playAlert(1, "Blow")
