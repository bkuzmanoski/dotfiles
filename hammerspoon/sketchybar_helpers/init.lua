local module = {}

-- Allow Sketchybar to query app names, window titles, etc.
require("hs.ipc")

-- Signal window change events to Sketchybar
local windowChange = require("sketchybar_helpers.window_change")
module.windowTitleIgnoreApps = windowChange.ignoreApps
module.windowTitleMaxLength = windowChange.titleMaxLength
module.windowTitlePatternsToRemove = windowChange.titlePatternsToRemove

-- Offset window positions to make room for Sketchybar on non-notch displays
local offsetWindows = require("sketchybar_helpers.offset_windows")
module.windowOffsetIgnoreDisplay = offsetWindows.ignoreDisplay
module.windowOffsetIgnoreApps = offsetWindows.ignoreApps
module.windowOffsetStatusbarOffset = offsetWindows.statusbarOffset
module.windowOffsetPadding = offsetWindows.padding

function module.init()
  windowChange.init()
  offsetWindows.init()
end

function module.cleanup()
  windowChange.cleanup()
  offsetWindows.cleanup()
end

return module
