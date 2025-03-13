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

function module.isExactModifiersMatch(requiredModifiers, flags)
  local allModifiers = { "cmd", "alt", "shift", "ctrl", "fn", "capslock" }
  local requiredLookup = {}
  local requiredCount = 0
  for _, modifier in ipairs(requiredModifiers) do
    requiredLookup[modifier] = true
    requiredCount = requiredCount + 1
  end

  local matchedCount = 0
  for _, modifier in ipairs(allModifiers) do
    local isRequired = requiredLookup[modifier] or false
    local isPressed = flags[modifier] or false

    if isRequired ~= isPressed then
      return false
    end
    if isRequired then
      matchedCount = matchedCount + 1
    end
  end

  return matchedCount == requiredCount
end

function module.playAlert()
  local alertSound = hs.sound.getByFile("/System/Library/Sounds/Tink.aiff") -- a.k.a. "Boop"
  if alertSound then
    alertSound:play()
  end
end

return module
