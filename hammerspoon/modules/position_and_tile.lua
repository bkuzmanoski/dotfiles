local utils = require("utils")
local module = {}
local bindings = {}
local topOffset, padding, splitRatios, tileTopBottomSplitRatioIndex, currentSplitRatioIndex, windowFilter, lastDirection, lastWindow

local function getWindows()
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow or focusedWindow:isFullscreen() or not focusedWindow:isMaximizable() then
    return nil, nil, nil
  end

  local screen = focusedWindow:screen()
  local windows = windowFilter:getWindows()
  for _, secondWindow in ipairs(windows) do
    if secondWindow:screen() == screen and secondWindow ~= focusedWindow and secondWindow:isMaximizable() then
      return screen, focusedWindow, secondWindow
    end
  end

  return screen, focusedWindow, nil
end

local function position(location)
  local screen, window = getWindows()
  if not screen or not window then
    utils.playAlert()
    return
  end

  local screenFrame = utils.getAdjustedScreenFrame(screen:fullFrame(), topOffset, padding)
  local windowFrame = window:frame()

  if location == "center" or location == "reasonableSize" or location == "almostMaximize" then
    if location == "reasonableSize" then
      windowFrame.h = math.floor(screenFrame.h * 0.6)
      windowFrame.w = math.floor(windowFrame.h * 1.3)
    end
    if location == "almostMaximize" then
      windowFrame.w = math.floor(screenFrame.w * 0.9)
      windowFrame.h = math.floor(screenFrame.h * 0.9)
    end
    windowFrame.x = screenFrame.x + math.floor((screenFrame.w - windowFrame.w) / 2)
    windowFrame.y = screenFrame.y + math.floor((screenFrame.h - windowFrame.h) / 2)
  elseif location == "maximize" then
    windowFrame = screenFrame
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

  local splitRatio = splitRatios[currentSplitRatioIndex]
  local screenFrame = utils.getAdjustedScreenFrame(screen:fullFrame(), topOffset, padding)
  screenFrame.w = screenFrame.w - padding

  local leftFrame = screenFrame:copy()
  leftFrame.w = math.floor(screenFrame.w * (direction == "left" and splitRatio or (1 - splitRatio)))

  local rightFrame = screenFrame:copy()
  rightFrame.x = screenFrame.x + leftFrame.w + padding
  rightFrame.w = screenFrame.w - leftFrame.w

  if direction == "left" or direction == "leftAndRight" then
    firstWindow:setFrame(leftFrame)
    if direction == "leftAndRight" and secondWindow then secondWindow:setFrame(rightFrame) end
    currentSplitRatioIndex = (currentSplitRatioIndex - 2) % #splitRatios + 1
    return
  end

  if direction == "right" or direction == "rightAndLeft" then
    firstWindow:setFrame(rightFrame)
    if direction == "rightAndLeft" and secondWindow then secondWindow:setFrame(leftFrame) end
    currentSplitRatioIndex = currentSplitRatioIndex % #splitRatios + 1
  end
end

local function tileTopRightBottomRight(direction)
  local screen, firstWindow, secondWindow = getWindows()
  if not screen or not firstWindow then
    utils.playAlert()
    return
  end

  local splitRatio = splitRatios[tileTopBottomSplitRatioIndex]
  local screenFrame = utils.getAdjustedScreenFrame(screen:fullFrame(), topOffset, padding)
  screenFrame.w = screenFrame.w - padding
  screenFrame.h = screenFrame.h - padding

  local topFrame = screenFrame:copy()
  topFrame.w = math.floor(screenFrame.w * splitRatio)
  topFrame.h = math.floor(screenFrame.h / 2)
  topFrame.x = screenFrame.x + screenFrame.w + padding - topFrame.w

  local bottomFrame = topFrame:copy()
  bottomFrame.h = screenFrame.h - topFrame.h
  bottomFrame.y = screenFrame.y + topFrame.h + padding

  if direction == "topRight" or direction == "topAndBottomRight" then
    firstWindow:setFrame(topFrame)
    if direction == "topAndBottomRight" and secondWindow then secondWindow:setFrame(bottomFrame) end
    return
  end

  if direction == "bottomRight" or direction == "bottomAndTopRight" then
    firstWindow:setFrame(bottomFrame)
    if direction == "bottomAndTopRight" and secondWindow then secondWindow:setFrame(topFrame) end
  end
end

function module.init(config)
  if next(bindings) or windowFilter then module.cleanup() end

  if config and config.hotkeys then
    local handlers = {
      -- Positioning
      positionCenter = function() position("center") end,
      positionReasonableSize = function() position("reasonableSize") end,
      positionAlmostMaximize = function() position("almostMaximize") end,
      positionMaximize = function() position("maximize") end,

      -- Horizontal tiling
      tileLeft = function() tileLeftRight("left") end,
      tileRight = function() tileLeftRight("right") end,
      tileLeftAndRight = function() tileLeftRight("leftAndRight") end,
      tileRightAndLeft = function() tileLeftRight("rightAndLeft") end,

      -- Vertical tiling
      tileTopRight = function() tileTopRightBottomRight("topRight") end,
      tileBottomRight = function() tileTopRightBottomRight("bottomRight") end,
      tileTopAndBottomRight = function() tileTopRightBottomRight("topAndBottomRight") end,
      tileBottomAndTopRight = function() tileTopRightBottomRight("bottomAndTopRight") end,
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
      tileTopBottomSplitRatioIndex = config.tileTopBottomSplitRatioIndex or 2

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
