local module = {}

function module.getCurrentSpaceIndex(screen)
  if not screen then
    return nil, nil
  end

  local activeSpaceID = hs.spaces.activeSpaceOnScreen(screen)

  if not activeSpaceID then
    return nil, nil
  end

  local spacesForScreen = hs.spaces.spacesForScreen(screen)

  if not spacesForScreen then
    return nil, nil
  end

  for index, spaceID in ipairs(spacesForScreen) do
    if spaceID == activeSpaceID then
      return index, #spacesForScreen
    end
  end

  return nil, nil
end

function module.getAdjustedScreenFrame(screen, topOffset, padding)
  local screenFrame = screen:frame()
  screenFrame.x = screenFrame.x + padding
  screenFrame.y = screenFrame.y + topOffset + padding
  screenFrame.w = screenFrame.w - (padding * 2)
  screenFrame.h = screenFrame.h - topOffset - (padding * 2)

  return screenFrame
end

function module.getAdjustedWindowFrame(adjustedScreenFrame, windowFrame)
  local adjustedWindowFrame = windowFrame:copy()

  adjustedWindowFrame.w = math.min(adjustedWindowFrame.w, adjustedScreenFrame.w)
  adjustedWindowFrame.h = math.min(adjustedWindowFrame.h, adjustedScreenFrame.h)

  local minX = adjustedScreenFrame.x
  local minY = adjustedScreenFrame.y
  local maxX = adjustedScreenFrame.x + adjustedScreenFrame.w
  local maxY = adjustedScreenFrame.y + adjustedScreenFrame.h

  adjustedWindowFrame.x = module.clamp(adjustedWindowFrame.x, minX, maxX - adjustedWindowFrame.w)
  adjustedWindowFrame.y = module.clamp(adjustedWindowFrame.y, minY, maxY - adjustedWindowFrame.h)

  return adjustedWindowFrame
end

function module.adjustWindowFrame(window, topOffset, padding)
  if not window or not window:isMaximizable() or window:title() == "" then
    return
  end

  local screen = window:screen()
  local windowFrame = window:frame()
  local adjustedScreenFrame = module.getAdjustedScreenFrame(screen, topOffset, padding)
  local adjustedWindowFrame = module.getAdjustedWindowFrame(adjustedScreenFrame, windowFrame)

  if
      windowFrame.x ~= adjustedWindowFrame.x or
      windowFrame.y ~= adjustedWindowFrame.y or
      windowFrame.w ~= adjustedWindowFrame.w or
      windowFrame.h ~= adjustedWindowFrame.h
  then
    window:setFrame(adjustedWindowFrame, 0)
  end
end

function module.getWindowUnderMouse(windows, validSubroles)
  local rawMousePosition = hs.mouse.absolutePosition()
  local elementUnderMouse = hs.axuielement.systemWideElement():elementAtPosition(rawMousePosition)

  if elementUnderMouse then
    local currentElement = elementUnderMouse

    while currentElement do
      local rawWindow = currentElement:attributeValue("AXWindow")

      if rawWindow then
        local subrole = rawWindow:attributeValue("AXSubrole")

        if subrole and validSubroles[subrole] then
          return rawWindow:asHSWindow()
        end
      end

      currentElement = currentElement:attributeValue("AXParent")
    end
  end

  local mousePosition = hs.geometry.new(rawMousePosition)

  for _, window in ipairs(windows) do
    if mousePosition:inside(window:frame()) then return window end
  end

  return nil
end

function module.clamp(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end

  if value > maxValue then
    return maxValue
  end

  return value
end

function module.cycleNext(array, afterIndex)
  if not afterIndex then
    return array[1]
  end

  for index, value in ipairs(array) do
    if value == afterIndex then
      return array[(index % #array) + 1]
    end
  end

  return array[1]
end

function module.createSpaces(numberOfSpaces)
  if not numberOfSpaces then
    return
  end

  local primaryScreen = hs.screen.primaryScreen()
  local spacesCount = #hs.spaces.spacesForScreen(primaryScreen)

  if numberOfSpaces <= spacesCount then
    return
  end

  for _ = spacesCount + 1, numberOfSpaces do
    hs.spaces.addSpaceToScreen(primaryScreen)
  end
end

function module.playAlert(repeatCount, soundNameOrPath)
  if not soundNameOrPath then
    soundNameOrPath = "Tink"
  end

  local sound = hs.sound.getByName(soundNameOrPath) or hs.sound.getByFile(soundNameOrPath)

  if not sound then
    return
  end

  if repeatCount == nil then
    repeatCount = 1
  end

  local playCount = 0

  local function playSound(state)
    if playCount == repeatCount or state == false then
      return
    end

    playCount = playCount + 1
    sound:play()
  end

  sound:setCallback(playSound)
  playSound()
end

return module
