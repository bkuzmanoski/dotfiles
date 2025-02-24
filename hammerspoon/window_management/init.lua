local module = {}

-- Focus the frontmost remaining window on the screen when the focused window is
-- closed (e.g. prevent the focus from moving to another space or the Desktop)
module.focusAfterClose = require("window_management.focus_after_close")

-- Move focus to the window to the left or right of the focused window
module.focusLeftRight = require("window_management.focus_left_right")

-- Focus the topmost window on the screen when the mouse enters it
module.focusScreen = require("window_management.focus_screen")

-- Apply window padding and maintain an offset from the top of the screen
module.position = require("window_management.position")

-- Move and resize windows
module.moveAndResize = require("window_management.move_and_resize")

-- Tile windows
module.tile = require("window_management.tile")

-- Move windows to space 1~5
module.moveToSpace = require("window_management.move_to_space")

function module.init()
  module.focusAfterClose.init()
  module.focusLeftRight.init()
  module.focusScreen.init()
  module.position.init()
  module.moveAndResize.init()
  module.tile.init()
  module.moveToSpace.init()
end

function module.cleanup()
  module.focusAfterClose.cleanup()
  module.focusLeftRight.cleanup()
  module.focusScreen.cleanup()
  module.position.cleanup()
  module.moveAndResize.cleanup()
  module.tile.cleanup()
  module.moveToSpace.cleanup()
end

return module
