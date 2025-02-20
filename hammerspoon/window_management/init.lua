local module = {}

-- Focus the topmost window on the screen when the mouse enters it
local screenFocus = require("window_management.screen_focus")

-- Move focus to the window to the left or right of the focused window
local focusLeftRight = require("window_management.focus_left_right")
module.focusLeftRightHotkeys = focusLeftRight.hotkeys

-- Move and resize windows
local moveAndResize = require("window_management.move_and_resize")
module.amount = moveAndResize.amount
module.moveHotkeys = moveAndResize.moveHotkeys
module.resizeHotkeys = moveAndResize.resizeHotkeys

-- Tile windows
local tile = require("window_management.tile")
module.tileGap = tile.gap
module.tileHotkeys = tile.hotkeys

function module.init()
  screenFocus.init()
  focusLeftRight.init()
  moveAndResize.init()
  tile.init()
end

function module.cleanup()
  screenFocus.cleanup()
  focusLeftRight.cleanup()
  moveAndResize.cleanup()
  tile.cleanup()
end

return module
