local utils = require("utils")
local module = {}
local bindings = {}
local splitRatios = { 0.5, 0.33, 0.67 }
local currentSplitRatioIndex = 1
local lastDirection, lastWindow

module.topOffset = 0
module.padding = 0
module.moveAndResizeAmount = 0
module.hotkeys = {
  positionCenter = {},
  positionReasonableSize = {},
  positionAlmostMaximize = {},
  positionMaximize = {},
  positionTopRight = {},
  positionBottomCenter = {},
  tileLeft = {},
  tileLeftAndRight = {},
  tileRight = {},
  tileRightAndLeft = {},
  tileTopRight = {},
  tileBottomRight = {},
  tileTopAndBottomRight = {},
  tileBottomAndTopRight = {}
}

local function getWindows()
  local focusedWindow = hs.window.focusedWindow()
  local screen = focusedWindow:screen()

  if not focusedWindow or
      focusedWindow:isFullscreen() or
      not focusedWindow:isMaximizable() then
    return nil, nil, nil
  end

  local windows = hs.window.orderedWindows()
  for _, window in ipairs(windows) do
    if window ~= focusedWindow and
        window:screen() == screen and
        not window:isFullscreen() and
        window:isMaximizable() and
        window:isVisible() then
      return screen, focusedWindow, window
    end
  end

  return screen, focusedWindow, nil
end

local function getAdjustedScreenFrame(screenFrame, topOffset, padding)
  screenFrame.x = screenFrame.x + padding
  screenFrame.y = screenFrame.y + topOffset + padding
  screenFrame.w = screenFrame.w - (2 * padding)
  screenFrame.h = screenFrame.h - topOffset - (2 * padding)
  return screenFrame
end

local function position(location)
  local screen, window = getWindows()
  if not screen or not window then
    utils.playAlert()
    return
  end

  local screenFrame = getAdjustedScreenFrame(screen:fullFrame(), module.topOffset, module.padding)
  local windowFrame = window:frame()

  if location == "center" or location == "reasonableSize" or location == "almostMaximize" then
    if location == "reasonableSize" then
      windowFrame.w = 800
      windowFrame.h = 600
    end
    if location == "almostMaximize" then
      windowFrame.w = math.floor(screenFrame.w * 0.9)
      windowFrame.h = math.floor(screenFrame.h * 0.9)
    end
    windowFrame.x = screenFrame.x + math.floor((screenFrame.w - windowFrame.w) / 2)
    windowFrame.y = screenFrame.y + math.floor((screenFrame.h - windowFrame.h) / 2)
  elseif location == "maximize" then
    windowFrame = screenFrame
  elseif location == "topRight" then
    windowFrame.x = screenFrame.x + screenFrame.w - windowFrame.w
    windowFrame.y = screenFrame.y
  elseif location == "bottomCenter" then
    windowFrame.x = screenFrame.x + math.floor((screenFrame.w - windowFrame.w) / 2)
    windowFrame.y = screenFrame.y + screenFrame.h - windowFrame.h
  end

  window:setFrame(windowFrame)
end

local function tileLeftRight(direction)
  local screen, firstWindow, secondWindow = getWindows()
  if not screen or not firstWindow then
    utils.playAlert()
    return
  end

  if firstWindow ~= lastWindow or lastDirection ~= direction then
    currentSplitRatioIndex = 1
    lastDirection = direction
    lastWindow = firstWindow
  end

  local ratio = splitRatios[currentSplitRatioIndex]
  local screenFrame = getAdjustedScreenFrame(screen:fullFrame(), module.topOffset, module.padding)
  screenFrame.w = screenFrame.w - module.padding

  local leftFrame = screenFrame:copy()
  leftFrame.w = math.floor(screenFrame.w * (direction == "left" and ratio or (1 - ratio)))

  local rightFrame = screenFrame:copy()
  rightFrame.x = screenFrame.x + leftFrame.w + module.padding
  rightFrame.w = screenFrame.w - leftFrame.w

  if direction == "left" or direction == "leftAndRight" then
    firstWindow:setFrame(leftFrame)
    if direction == "leftAndRight" and secondWindow then
      secondWindow:setFrame(rightFrame)
    end

    currentSplitRatioIndex = (currentSplitRatioIndex - 2) % #splitRatios + 1
    return
  end

  if direction == "right" or direction == "rightAndLeft" then
    firstWindow:setFrame(rightFrame)
    if direction == "rightAndLeft" and secondWindow then
      secondWindow:setFrame(leftFrame)
    end

    currentSplitRatioIndex = currentSplitRatioIndex % #splitRatios + 1
  end
end

local function tileTopBottom(direction)
  local screen, firstWindow, secondWindow = getWindows()
  if not screen or not firstWindow then
    utils.playAlert()
    return
  end

  local ratio = splitRatios[2] -- 1/3
  local screenFrame = getAdjustedScreenFrame(screen:fullFrame(), module.topOffset, module.padding)
  screenFrame.w = screenFrame.w - module.padding
  screenFrame.h = screenFrame.h - module.padding

  local topFrame = screenFrame:copy()
  topFrame.w = math.floor(screenFrame.w * ratio)
  topFrame.h = math.floor(screenFrame.h / 2)
  topFrame.x = screenFrame.x + screenFrame.w + module.padding - topFrame.w

  local bottomFrame = topFrame:copy()
  bottomFrame.h = screenFrame.h - topFrame.h
  bottomFrame.y = screenFrame.y + topFrame.h + module.padding

  if direction == "topRight" or direction == "topAndBottomRight" then
    firstWindow:setFrame(topFrame)
    if direction == "topAndBottomRight" and secondWindow then
      secondWindow:setFrame(bottomFrame)
    end

    return
  end

  if direction == "bottomRight" or direction == "bottomAndTopRight" then
    firstWindow:setFrame(bottomFrame)
    if direction == "bottomAndTopRight" and secondWindow then
      secondWindow:setFrame(topFrame)
    end
  end
end

function module.init()
  local handlers = {
    -- Positioning handlers
    positionCenter = function() position("center") end,
    positionReasonableSize = function() position("reasonableSize") end,
    positionAlmostMaximize = function() position("almostMaximize") end,
    positionMaximize = function() position("maximize") end,
    positionTopRight = function() position("topRight") end,
    positionBottomCenter = function() position("bottomCenter") end,

    -- Horizontal tiling handlers
    tileLeft = function() tileLeftRight("left") end,
    tileRight = function() tileLeftRight("right") end,
    tileLeftAndRight = function() tileLeftRight("leftAndRight") end,
    tileRightAndLeft = function() tileLeftRight("rightAndLeft") end,

    -- Vertical tiling handlers
    tileTopRight = function() tileTopBottom("topRight") end,
    tileBottomRight = function() tileTopBottom("bottomRight") end,
    tileTopAndBottomRight = function() tileTopBottom("topAndBottomRight") end,
    tileBottomAndTopRight = function() tileTopBottom("bottomAndTopRight") end,
  }

  for name, hotkey in pairs(module.hotkeys) do
    if next(hotkey) and handlers[name] then
      bindings[name] = hs.hotkey.bind(
        hotkey.modifiers,
        hotkey.key,
        handlers[name]
      )
    end
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
