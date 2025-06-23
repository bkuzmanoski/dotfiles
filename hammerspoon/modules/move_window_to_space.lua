local utils = require("utils")

local module = {}
local bindings = {}

local function getFocusedWindowAndScreen()
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow or not focusedWindow:isStandard() or focusedWindow:isFullscreen() then return nil, nil end

  local screen = focusedWindow:screen()
  return focusedWindow, screen
end

local function getCurrentSpace(screen)
  local spacesData = hs.spaces.data_managedDisplaySpaces()
  if not spacesData then return nil, nil end

  local targetScreen
  for _, display in ipairs(spacesData) do
    if display["Display Identifier"] == screen:getUUID() then
      targetScreen = display
      break
    end
  end
  if not targetScreen then return nil, nil end

  local numberOfSpaces = #targetScreen.Spaces
  if numberOfSpaces == 1 then return nil, nil end

  local currentSpaceId = targetScreen["Current Space"].ManagedSpaceID
  for i, space in ipairs(targetScreen.Spaces) do
    if space.ManagedSpaceID == currentSpaceId then
      return i, numberOfSpaces
    end
  end

  return nil, nil
end

local function moveWindowToSpace(window, spaceNumber)
  local frame = window:frame()
  local mousePosition = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, { x = frame.x + 5, y = frame.y + 20 }):post()
  hs.timer.usleep(300000)
  hs.eventtap.keyStroke({ "ctrl" }, tostring(spaceNumber), 0)
  hs.timer.usleep(300000)
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, { x = frame.x + 5, y = frame.y + 20 }):post()
  hs.mouse.absolutePosition(mousePosition)
end

local function moveWindowToPreviousSpace()
  local window, screen = getFocusedWindowAndScreen()
  if not (window and screen) then return end

  local currentSpaceNumber, numberOfSpaces = getCurrentSpace(screen)
  if not (currentSpaceNumber and numberOfSpaces) then return end
  moveWindowToSpace(window, ((currentSpaceNumber - 2 + numberOfSpaces) % numberOfSpaces) + 1)
end

local function moveWindowToNextSpace()
  local window, screen = getFocusedWindowAndScreen()
  if not (window and screen) then return end

  local currentSpaceNumber, numberOfSpaces = getCurrentSpace(screen)
  if not (currentSpaceNumber and numberOfSpaces) then return end
  moveWindowToSpace(window, (currentSpaceNumber % numberOfSpaces) + 1)
end

function module.init(config)
  if next(bindings) then module.cleanup() end

  if config and config.modifiers then
    if config.keys then
      local handlers = { previousSpace = moveWindowToPreviousSpace, nextSpace = moveWindowToNextSpace }
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
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
