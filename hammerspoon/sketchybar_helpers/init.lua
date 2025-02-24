local module = {}

-- Signal window change events to Sketchybar to update the window title
module.windowTitle = require("sketchybar_helpers.window_title")

function module.init()
  module.windowTitle.init()
end

function module.cleanup()
  module.windowTitle.cleanup()
end

return module
