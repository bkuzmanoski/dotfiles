local utils = require("utils")
local module = {}
local bindings = {}
local windowFilter

module.hotkeys = {
  frontmost = {},
  left = {},
  right = {}
}

local function focusWindow(direction)
  local windows = windowFilter:getWindows()
  if #windows == 0 then
    utils.playAlert()
    return
  end

  if direction == "frontmost" then
    windows[1]:focus()
    return
  end

  local currentWindow = hs.window.focusedWindow()
  local screen = currentWindow:screen()
  local referenceFrame = hs.window.focusedWindow():frame()
  local candidateWindow = nil
  local minXDiff = math.huge
  for _, window in ipairs(windows) do
    if window:screen() == screen and window ~= currentWindow then
      local frame = window:frame()
      if direction == "left" and frame.x < referenceFrame.x then
        local diff = referenceFrame.x - frame.x
        if diff < minXDiff then
          candidateWindow = window
          minXDiff = diff
        end
      elseif direction == "right" and frame.x > referenceFrame.x then
        local diff = frame.x - referenceFrame.x
        if diff < minXDiff then
          candidateWindow = window
          minXDiff = diff
        end
      end
    end
  end

  if candidateWindow then
    candidateWindow:focus()
  else
    local fallbackWindow = nil
    local minX = math.huge
    local maxX = -math.huge
    for _, window in ipairs(windows) do
      if window:screen() == screen and window ~= currentWindow then
        local frame = window:frame()
        if direction == "left" and frame.x > maxX then
          maxX = frame.x
          fallbackWindow = window
        elseif direction == "right" and frame.x < minX then
          minX = frame.x
          fallbackWindow = window
        end
      end
    end
    if fallbackWindow then
      fallbackWindow:focus()
    else
      utils.playAlert()
    end
  end
end

function module.init()
  for window, hotkey in pairs(module.hotkeys) do
    bindings[window] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, function() focusWindow(window) end)
  end
  if next(bindings) then
    windowFilter = hs.window.filter.new():setOverrideFilter({
      allowRoles = { "AXStandardWindow" },
      allowTitles = 1,
      currentSpace = true,
      fullscreen = false,
      visible = true
    })
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
  windowFilter = nil
end

return module
