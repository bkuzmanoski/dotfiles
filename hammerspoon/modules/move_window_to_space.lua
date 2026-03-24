local module = {}

local utils = require("utils")

local bindings = {}

local function getFocusedWindowAndScreen()
  local focusedWindow = hs.window.frontmostWindow()

  if not focusedWindow or not focusedWindow:isStandard() or focusedWindow:isFullscreen() then
    return nil, nil
  end

  return focusedWindow, focusedWindow:screen()
end

local function moveWindowToSpace(window, spaceNumber)
  local zoomButtonRect = window:zoomButtonRect()

  if not zoomButtonRect then
    return
  end

  local mousePosition = hs.mouse.absolutePosition()
  local windowTarget = { x = zoomButtonRect.x + zoomButtonRect.w + 5, y = zoomButtonRect.y + (zoomButtonRect.h / 2) }

  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, windowTarget):post()
  hs.timer.usleep(300000)
  hs.eventtap.keyStroke({ "ctrl" }, tostring(spaceNumber), 0)
  hs.timer.usleep(300000)
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, windowTarget):post()
  hs.mouse.absolutePosition(mousePosition)
end

local function moveFocusedWindow(space)
  local window, screen = getFocusedWindowAndScreen()

  if not window or not screen then
    return
  end

  if space == "left" or space == "right" then
    local currentSpaceNumber, numberOfSpaces = utils.getCurrentSpaceIndex(screen)

    if not currentSpaceNumber or not numberOfSpaces then
      return
    end

    moveWindowToSpace(
      window,
      space == "left" and ((currentSpaceNumber - 2 + numberOfSpaces) % numberOfSpaces) + 1
      or (currentSpaceNumber % numberOfSpaces) + 1
    )
  else
    moveWindowToSpace(window, space)
  end
end

function module.init(config)
  if next(bindings) then
    module.cleanup()
  end

  if not config then
    return module
  end

  for action, hotkey in pairs(config) do
    if action == "left" or action == "right" then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, function()
        moveFocusedWindow(action)
      end)
    elseif action == "index" then
      for spaceIndex = 1, math.min(hotkey.maximumSpaces or 9, 9) do
        bindings[action .. spaceIndex] = hs.hotkey.bind(hotkey.modifiers, tostring(spaceIndex), function()
          moveFocusedWindow(spaceIndex)
        end)
      end
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end

  bindings = {}
end

return module
