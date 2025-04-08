local module = {}

function module.getAdjustedScreenFrame(screenFullFrame, topOffset, padding)
  local menuBar = hs.axuielement.systemElementAtPosition(0, 0)
  if menuBar and menuBar:attributeValue("AXRole") == "AXMenuBar" then
    topOffset = topOffset + menuBar:attributeValue("AXSize").h
  end

  screenFullFrame.x = screenFullFrame.x + padding
  screenFullFrame.y = screenFullFrame.y + topOffset + padding
  screenFullFrame.w = screenFullFrame.w - (padding * 2)
  screenFullFrame.h = screenFullFrame.h - topOffset - (padding * 2)
  return screenFullFrame
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

function module.playAlert()
  local alertSound = hs.sound.getByFile("/System/Library/Sounds/Tink.aiff") -- a.k.a. "Boop"
  if alertSound then alertSound:play() end
end

return module
