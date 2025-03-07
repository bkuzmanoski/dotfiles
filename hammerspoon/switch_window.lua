local utils = require("utils")
local module = {}
local bindings = {}

module.hotkeys = {
  focusFrontmost = {},
  hints = {},
  left = {},
  right = {}
}

local function setUpWindowHints()
  hs.hints.fontName = "SFPro-Medium"
  hs.hints.fontSize = 13
  hs.hints.showTitleThresh = 0
  hs.hints.style = "vimperator"
end

local function focusWindow(direction)
  local windows = hs.window.filter.new():setOverrideFilter({
    allowRoles = { "AXStandardWindow" },
    currentSpace = true,
    fullscreen = false,
    visible = true
  }):getWindows()
  if #windows == 0 then
    utils.playAlert()
    return
  end

  if direction == "frontmost" then
    windows[1]:focus()
  end

  local currentWindow = hs.window.focusedWindow()
  local referenceFrame = hs.window.focusedWindow():frame()
  local candidateWindow = nil
  local minXDiff = math.huge
  for _, window in ipairs(windows) do
    if window ~= currentWindow then
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
  if next(module.hotkeys.focusFrontmost) then
    bindings.focusFrontmost = hs.hotkey.bind(
      module.hotkeys.focusFrontmost.modifiers,
      module.hotkeys.focusFrontmost.key,
      function()
        focusWindow("frontmost")
      end)
  end
  if next(module.hotkeys.hints) then
    setUpWindowHints()
    bindings.hints = hs.hotkey.bind(
      module.hotkeys.hints.modifiers,
      module.hotkeys.hints.key,
      hs.hints.windowHints)
  end
  if next(module.hotkeys.left) then
    bindings.left = hs.hotkey.bind(
      module.hotkeys.left.modifiers,
      module.hotkeys.left.key,
      function()
        focusWindow("left")
      end)
  end
  if next(module.hotkeys.right) then
    bindings.right = hs.hotkey.bind(
      module.hotkeys.right.modifiers,
      module.hotkeys.right.key,
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
