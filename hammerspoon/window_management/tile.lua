local module = {}

module.gap = 8
module.hotkeys = {
  left = { modifiers = { "option", "command" }, key = "l" },
  right = { modifiers = { "option", "command" }, key = "'" }
}

local hotkeyTileLeft, hotkeyTileRight
local splitRatios = { 0.5, 0.33, 0.67 } -- 2 significant figures for thirds matches Raycast's behavior
local currentSplitRatioIndex = 1
local lastDirection = nil
local lastWindow = nil
local alertSound = hs.sound.getByFile("/System/Library/Sounds/Tink.aiff")

local function playAlert()
  if alertSound then
    alertSound:play()
  end
end

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

  -- Play alert sound if there is no window to tile or the window cannot be resized
  if not screen or not firstWindow then
    playAlert()
    return
  end

  -- Reset the current split ratio index if the frontmost window or tile direction has changed
  if firstWindow ~= lastWindow or lastDirection ~= direction then
    currentSplitRatioIndex = 1
    lastDirection = direction
    lastWindow = firstWindow
  end

  -- Offset the screen frame to account for the gap
  local ratio = splitRatios[currentSplitRatioIndex]
  local screenFrame = screen:frame():copy()
  screenFrame.x = screenFrame.x + module.gap
  screenFrame.y = screenFrame.y + module.gap
  screenFrame.w = screenFrame.w - 3 * module.gap
  screenFrame.h = screenFrame.h - 2 * module.gap

  -- Determine the frames for the left and right windows based on the split ratio
  local leftFrame = screenFrame:copy()
  leftFrame.w = math.floor(screenFrame.w * (direction == "left" and ratio or (1 - ratio)))

  local rightFrame = screenFrame:copy()
  rightFrame.x = screenFrame.x + leftFrame.w + module.gap
  rightFrame.w = screenFrame.w - leftFrame.w

  -- Set the window frames to tile the windows
  if direction == "left" then
    firstWindow:setFrame(leftFrame)
    if secondWindow then secondWindow:setFrame(rightFrame) end
  else
    firstWindow:setFrame(rightFrame)
    if secondWindow then secondWindow:setFrame(leftFrame) end
  end

  -- Cycle through the split ratios
  currentSplitRatioIndex = currentSplitRatioIndex % #splitRatios + 1
end

function module.init()
  -- Bind hotkeys to tile windows
  module.hotkeyTileLeft = hs.hotkey.bind(module.hotkeys.left.modifiers, module.hotkeys.left.key, function()
    tileWindows("left")
  end)

  module.hotkeyTileRight = hs.hotkey.bind(module.hotkeys.right.modifiers, module.hotkeys.right.key, function()
    tileWindows("right")
  end)
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
