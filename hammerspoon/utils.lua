local module = {}

function module.getAdjustedWindowFrame(screenFrame, windowFrame, topOffset, padding)
  local adjustedWindowFrame = windowFrame:copy()
  if adjustedWindowFrame.x - screenFrame.x < (padding) then
    adjustedWindowFrame.x = screenFrame.x + padding
    if (screenFrame.x + screenFrame.w) - (adjustedWindowFrame.x + adjustedWindowFrame.w) < padding then
      adjustedWindowFrame.w = screenFrame.w - (padding * 2)
    end
  end
  if adjustedWindowFrame.y - screenFrame.y < (topOffset + padding) then
    adjustedWindowFrame.y = screenFrame.y + topOffset + padding
    if (screenFrame.y + screenFrame.h) - (adjustedWindowFrame.y + adjustedWindowFrame.h) < padding then
      adjustedWindowFrame.h = screenFrame.h - topOffset - (padding * 2)
    end
  end

  return adjustedWindowFrame
end

function module.playAlert()
  local alertSound = hs.sound.getByFile("/System/Library/Sounds/Tink.aiff") -- a.k.a. "Boop"
  if alertSound then
    alertSound:play()
  end
end

return module
