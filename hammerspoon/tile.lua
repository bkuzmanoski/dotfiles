local utils = require("utils")
local module = {}
local hotkeyTileLeft, hotkeyTileRight
local splitRatios = { 0.5, 0.33, 0.67 } -- 2 significant figures for thirds matches Raycast's behavior
local currentSplitRatioIndex = 1
local lastDirection, lastWindow

module.hotkeys = {
  left = {},
  right = {}
}
module.padding = 0


local function getWindows()
  local focusedWindow = hs.window.focusedWindow()
  local screen = focusedWindow:screen()

  if not focusedWindow or not focusedWindow:isMaximizable() then
    return nil, nil, nil
  end

  local windows = hs.window.orderedWindows()
  for _, window in ipairs(windows) do
    if window ~= focusedWindow and window:screen() == screen and window:isMaximizable() and window:isVisible() then
      return screen, focusedWindow, window
    end
  end

  return screen, focusedWindow, nil
end

local function tileWindows(direction)
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
  local screenFrame = screen:frame():copy()
  screenFrame.x = screenFrame.x + module.padding
  screenFrame.y = screenFrame.y + module.padding
  screenFrame.w = screenFrame.w - 3 * module.padding
  screenFrame.h = screenFrame.h - 2 * module.padding

  local leftFrame = screenFrame:copy()
  leftFrame.w = math.floor(screenFrame.w * (direction == "left" and ratio or (1 - ratio)))

  local rightFrame = screenFrame:copy()
  rightFrame.x = screenFrame.x + leftFrame.w + module.padding
  rightFrame.w = screenFrame.w - leftFrame.w

  if direction == "left" then
    firstWindow:setFrame(leftFrame)
    if secondWindow then secondWindow:setFrame(rightFrame) end
  else
    firstWindow:setFrame(rightFrame)
    if secondWindow then secondWindow:setFrame(leftFrame) end
  end

  currentSplitRatioIndex = currentSplitRatioIndex % #splitRatios + 1
end

function module.init()
  if next(module.hotkeys.left) then
    module.hotkeyTileLeft = hs.hotkey.bind(module.hotkeys.left.modifiers, module.hotkeys.left.key, function()
      tileWindows("left")
    end)
  end
  if next(module.hotkeys.right) then
    module.hotkeyTileRight = hs.hotkey.bind(module.hotkeys.right.modifiers, module.hotkeys.right.key, function()
      tileWindows("right")
    end)
  end
end

function module.cleanup()
  if hotkeyTileLeft then
    hotkeyTileLeft:delete()
    hotkeyTileLeft = nil
  end
  if hotkeyTileRight then
    hotkeyTileRight:delete()
    hotkeyTileRight = nil
  end
end

return module
