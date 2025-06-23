local module = {}

function module.getAdjustedScreenFrame(screen, topOffset, padding)
  local screenFrame = (topOffset and topOffset > 0) and screen:fullFrame() or screen:frame()
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
  if not window or not window:isMaximizable() or window:title() == "" then return end

  local windowFrame = window:frame()
  local adjustedScreenFrame = module.getAdjustedScreenFrame(window:screen(), topOffset, padding)
  local adjustedWindowFrame = module.getAdjustedWindowFrame(adjustedScreenFrame, windowFrame)
  if windowFrame.x ~= adjustedWindowFrame.x or windowFrame.y ~= adjustedWindowFrame.y then
    window:setFrame(adjustedWindowFrame, 0)
  end
end

function module.playAlert(repeatCount, soundNameOrPath)
  if not soundNameOrPath then soundNameOrPath = "Tink" end -- a.k.a. "Boop"
  local sound = hs.sound.getByName(soundNameOrPath)
  if not sound then sound = hs.sound.getByFile(soundNameOrPath) end
  if not sound then return end

  if repeatCount == nil then repeatCount = 1 end
  local playCount = 0
  local function playSound(state)
    if playCount == repeatCount or state == false then return end
    playCount = playCount + 1
    sound:play()
  end

  sound:setCallback(playSound)
  playSound()
end

return module
