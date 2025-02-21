local module = {}

-- Allow Sketchybar to query app names, window titles, etc.
require("hs.ipc")

-- Signal window change events to Sketchybar
local windowChange = require("sketchybar_helpers.window_change")
module.windowTitleMaxLength = windowChange.titleMaxLength
module.windowTitlePatternsToRemove = windowChange.titlePatternsToRemove

-- Offset window positions to make room for Sketchybar on non-notch displays
local offsetWindows = require("sketchybar_helpers.offset_windows")
module.notchDisplayName = offsetWindows.notchDisplayName
module.statusbarOffset = offsetWindows.statusbarOffset
module.bottomPadding = offsetWindows.bottomPadding

function module.init()
  windowChange.init()
  offsetWindows.init()
end

function module.cleanup()
  windowChange.cleanup()
  offsetWindows.cleanup()
end

return module
