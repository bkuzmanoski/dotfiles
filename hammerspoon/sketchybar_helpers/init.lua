local module = {}

-- Offset window positions to make room for Sketchybar on non-notch displays
local offsetWindows = require("sketchybar_helpers.offset_windows")
module.notchDisplayName = offsetWindows.notchDisplayName
module.statusbarOffset = offsetWindows.statusbarOffset
module.bottomPadding = offsetWindows.bottomPadding

function module.init()
  offsetWindows.init()
end

function module.cleanup()
  offsetWindows.cleanup()
end

return module
