local utils = require("utils")
local module = {}
local bindings = {}
local windowFilter

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
    -- Try focusing window to the left or right of the currently focused window
    if window:screen() == screen and window ~= currentWindow and window:title() ~= "" then
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
    return
  end

  -- If no candidate window was found, try focusing the leftmost or rightmost window
  local fallbackWindow = nil
  local minX = math.huge
  local maxX = -math.huge
  for _, window in ipairs(windows) do
    if window:screen() == screen and window ~= currentWindow and window:title() ~= "" then
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
    return
  end

  -- No window to focus was found
  utils.playAlert()
end

function module.init(config)
  if next(bindings) or windowFilter then module.cleanup() end

  if config then
    local handlers = {
      focusFrontmost = function() focusWindow("frontmost") end,
      focusLeft = function() focusWindow("left") end,
      focusRight = function() focusWindow("right") end
    }
    for action, hotkey in pairs(config) do
      if handlers[action] and hotkey.modifiers and hotkey.key then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
      end
    end

    if next(bindings) then
      windowFilter = hs.window.filter.new():setOverrideFilter({
        allowRoles = { "AXStandardWindow" },
        currentSpace = true,
        fullscreen = false,
        visible = true
      })
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}

  windowFilter = nil
end

return module
