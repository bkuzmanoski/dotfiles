local utils = require("utils")

local module = {}
local bindings = {}

local targetSpace = { previousSpace = "previousSpace", nextSpace = "nextSpace" }

local function getFocusedWindowAndScreen()
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow or not focusedWindow:isStandard() or focusedWindow:isFullscreen() then return nil, nil end

  return focusedWindow, focusedWindow:screen()
end

local function moveWindowToSpace(window, spaceNumber)
  local mousePosition = hs.mouse.absolutePosition()
  local zoomButtonRect = window:zoomButtonRect()
  if not zoomButtonRect then return end

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
  if not window or not screen then return end

  local currentSpaceNumber, numberOfSpaces = utils.getCurrentSpaceIndex(screen)
  if not currentSpaceNumber or not numberOfSpaces then return end

  if space == targetSpace.previousSpace then
    moveWindowToSpace(window, ((currentSpaceNumber - 2 + numberOfSpaces) % numberOfSpaces) + 1)
  elseif space == targetSpace.nextSpace then
    moveWindowToSpace(window, (currentSpaceNumber % numberOfSpaces) + 1)
  end
end

function module.init(config)
  if next(bindings) then module.cleanup() end

  if not config or not config.modifiers then return module end

  if config.keys then
    local handlers = {
      previousSpace = function() moveFocusedWindow(targetSpace.previousSpace) end,
      nextSpace = function() moveFocusedWindow(targetSpace.nextSpace) end,
    }
    for action, key in pairs(config.keys) do
      if handlers[action] then
        bindings[action] = hs.hotkey.bind(config.modifiers, key, handlers[action])
      end
    end
  end

  if config.enableNumberKeys then
    for i = 1, 9 do
      bindings[i] = hs.hotkey.bind(config.modifiers, tostring(i), function()
        local focusedWindow = getFocusedWindowAndScreen()
        if not focusedWindow then return end
        moveWindowToSpace(focusedWindow, i)
      end)
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
