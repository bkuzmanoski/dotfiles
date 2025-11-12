local module = {}

local utils = require("utils")
local direction = { left = "left", right = "right" }
local size = { small = "small", medium = "medium", large = "large", current = "current" }
local sizeConfigs = {
  [size.small] = { heightRatio = 0.7, widthAspectRatio = 1.3 },
  [size.medium] = { widthRatio = 0.9, heightRatio = 0.9 },
  [size.large] = { fillScreen = true },
  [size.current] = { keepCurrentSize = true }
}

local bindings = {}
local topOffset, padding, splitRatios
local currentSplitRatio, lastDirection, lastWindow

local function getFocusedWindowAndScreen()
  local focusedWindow = hs.window.frontmostWindow()

  if not focusedWindow or not focusedWindow:isMaximizable() or focusedWindow:isFullscreen() then
    return nil, nil
  end

  return focusedWindow, focusedWindow:screen()
end

local function center(targetSize)
  if not targetSize then
    return
  end

  local window, screen = getFocusedWindowAndScreen()

  if not window or not screen then
    return
  end

  local screenFrame = utils.getAdjustedScreenFrame(screen, topOffset, padding)
  local windowFrame = window:frame()
  local config = sizeConfigs[targetSize]

  if config.fillScreen then
    windowFrame = screenFrame
  else
    if config.widthAspectRatio then
      windowFrame.h = math.floor(screenFrame.h * config.heightRatio)
      windowFrame.w = math.floor(windowFrame.h * config.widthAspectRatio)
    elseif config.widthRatio and config.heightRatio then
      windowFrame.w = math.floor(screenFrame.w * config.widthRatio)
      windowFrame.h = math.floor(screenFrame.h * config.heightRatio)
    end

    windowFrame.x = screenFrame.x + math.floor((screenFrame.w - windowFrame.w) / 2)
    windowFrame.y = screenFrame.y + math.floor((screenFrame.h - windowFrame.h) / 2)
  end

  window:setFrame(windowFrame)
end

local function position(targetDirection)
  local window, screen = getFocusedWindowAndScreen()

  if not window or not screen then
    return
  end

  if not currentSplitRatio or window ~= lastWindow or lastDirection ~= targetDirection then
    currentSplitRatio = splitRatios[1]
    lastDirection = targetDirection
    lastWindow = window
  else
    currentSplitRatio = utils.cycleNext(splitRatios, currentSplitRatio)
  end

  local screenFrame = utils.getAdjustedScreenFrame(screen, topOffset, padding)
  screenFrame.w = screenFrame.w - padding

  local leftFrame = screenFrame:copy()
  leftFrame.w = math.floor(
    screenFrame.w * (targetDirection == direction.left and currentSplitRatio or (1 - currentSplitRatio))
  )

  local rightFrame = screenFrame:copy()
  rightFrame.x = screenFrame.x + leftFrame.w + padding
  rightFrame.w = screenFrame.w - leftFrame.w

  if targetDirection == direction.left then
    window:setFrame(leftFrame)
  elseif targetDirection == direction.right then
    window:setFrame(rightFrame)
  end
end

function module.init(config)
  if next(bindings) then
    module.cleanup()
  end

  if config and config.hotkeys then
    local handlers = {
      center = function()
        center(size.current)
      end,
      centerSmall = function()
        center(size.small)
      end,
      centerMedium = function()
        center(size.medium)
      end,
      centerLarge = function()
        center(size.large)
      end,
      left = function()
        position(direction.left)
      end,
      right = function()
        position(direction.right)
      end
    }

    for action, hotkey in pairs(config.hotkeys) do
      if handlers[action] then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
      end
    end

    if next(bindings) then
      topOffset = config.topOffset or 0
      padding = config.padding or 0
      splitRatios = config.splitRatios or { 0.5, 0.33, 0.67 }
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end

  bindings = {}
end

return module
