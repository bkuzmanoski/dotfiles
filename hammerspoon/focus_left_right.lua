local utils = require("utils")
local module = {}
local bindings = {}

module.hotkeys = {
  left = {},
  right = {}
}

local function focusWindow(direction)
  local currentWindow = hs.window.focusedWindow()
  if not currentWindow then
    utils.playAlert()
    return
  end

  local currentFrame = currentWindow:frame()
  local windows = hs.window.filter.new():setOverrideFilter({
    allowScreens = { currentWindow:screen():id() },
    allowRoles = { "AXStandardWindow" },
    currentSpace = true,
    fullscreen = false,
    visible = true
  }):getWindows()
  local candidateWindow = nil
  local minXDiff = math.huge
  for _, window in ipairs(windows) do
    if window ~= currentWindow then
      local frame = window:frame()
      if direction == "left" and frame.x < currentFrame.x then
        local diff = currentFrame.x - frame.x
        if diff < minXDiff then
          candidateWindow = window
          minXDiff = diff
        end
      elseif direction == "right" and frame.x > currentFrame.x then
        local diff = frame.x - currentFrame.x
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
      if window ~= currentWindow then
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
  if next(module.hotkeys.left) then
    bindings.left = hs.hotkey.bind(module.hotkeys.left.modifiers, module.hotkeys.left.key, function()
      focusWindow("left")
    end)
  end
  if next(module.hotkeys.right) then
    bindings.right = hs.hotkey.bind(module.hotkeys.right.modifiers, module.hotkeys.right.key,
      function()
        focusWindow("right")
      end)
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
