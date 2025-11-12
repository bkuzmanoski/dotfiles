local module = {}

function module.cycleNext(array, after)
  if not after then
    return array[1]
  end

  for i, value in ipairs(array) do
    if value == after then
      return array[(i % #array) + 1]
    end
  end

  return array[1]
end

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

  for i, spaceID in ipairs(spacesForScreen) do
    if spaceID == activeSpaceID then
      return i, #spacesForScreen
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

  if adjustedWindowFrame.x - adjustedScreenFrame.x < 0 then
    adjustedWindowFrame.x = adjustedScreenFrame.x

    if (adjustedScreenFrame.x + adjustedScreenFrame.w) - (adjustedWindowFrame.x + adjustedWindowFrame.w) < 0 then
      adjustedWindowFrame.w = adjustedScreenFrame.w
    end
  end
  if adjustedWindowFrame.y - adjustedScreenFrame.y < 0 then
    adjustedWindowFrame.y = adjustedScreenFrame.y

    if (adjustedScreenFrame.y + adjustedScreenFrame.h) - (adjustedWindowFrame.y + adjustedWindowFrame.h) < 0 then
      adjustedWindowFrame.h = adjustedScreenFrame.h
    end
  end

  return adjustedWindowFrame
end

function module.adjustWindowFrame(window, topOffset, padding)
  if not window or not window:isMaximizable() or window:title() == "" then
    return
  end

  local windowFrame = window:frame()
  local adjustedScreenFrame = module.getAdjustedScreenFrame(window:screen(), topOffset, padding)
  local adjustedWindowFrame = module.getAdjustedWindowFrame(adjustedScreenFrame, windowFrame)

  if windowFrame.x ~= adjustedWindowFrame.x or windowFrame.y ~= adjustedWindowFrame.y then
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
