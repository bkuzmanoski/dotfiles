local utils = require("utils")
local module = {}
local bindings = {}

module.allowDisplay = ""
module.numberOfSpaces = 0
module.hotkeys = {
  modifiers = {},
  previousSpaceKey = "",
  nextSpaceKey = ""
}
module.navigationHotkeyModifiers = {}

local function getFocusedWindowAndScreen()
  local focusedWindow = hs.window.focusedWindow()
  local screen = focusedWindow:screen()
  if screen:name() ~= module.allowDisplay or
      not focusedWindow or
      not focusedWindow:isStandard() or
      focusedWindow:isFullscreen() then
    utils.playAlert()
    return nil, nil
  end

  return focusedWindow, screen
end

local function getCurrentSpaceNumber(screen)
  local spacesData = hs.spaces.data_managedDisplaySpaces()
  if not spacesData then
    return nil, nil
  end

  local targetScreen
  for _, display in ipairs(spacesData) do
    if display["Display Identifier"] == screen:getUUID() then
      targetScreen = display
      break
    end
  end

  if not targetScreen then
    return nil, nil
  end

  local currentSpaceId = targetScreen["Current Space"].ManagedSpaceID
  for i, space in ipairs(targetScreen.Spaces) do
    if space.ManagedSpaceID == currentSpaceId then
      return i, #targetScreen.Spaces
    end
  end

  return nil, nil
end

local function moveWindowToSpace(window, spaceNumber)
  local frame = window:frame()
  local mousePosition = hs.mouse.absolutePosition()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, { x = frame.x + 5, y = frame.y + 20 }):post()
  hs.eventtap.keyStroke(module.navigationHotkeyModifiers, tostring(spaceNumber))
  hs.timer.usleep(100000) -- Avoid flicker resulting from "dropping" the window before the space animation completes
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, { x = frame.x + 5, y = frame.y + 20 }):post()
  hs.mouse.absolutePosition(mousePosition)
end

local function moveWindowToPreviousSpace()
  local window, screen = getFocusedWindowAndScreen()
  if not screen then
    return
  end

  local currentSpaceNumber, numberOfSpaces = getCurrentSpaceNumber(screen)
  if currentSpaceNumber and numberOfSpaces > 1 then
    moveWindowToSpace(window, (currentSpaceNumber % module.numberOfSpaces) + 1)
  end
end

local function moveWindowToNextSpace()
  local window, screen = getFocusedWindowAndScreen()
  if not screen then
    return
  end

  local currentSpaceNumber, numberOfSpaces = getCurrentSpaceNumber(screen)
  if currentSpaceNumber and numberOfSpaces > 1 then
    moveWindowToSpace(window, ((currentSpaceNumber - 2 + module.numberOfSpaces) % module.numberOfSpaces) + 1)
  end
end

function module.init()
  if module.numberOfSpaces > 1 and module.numberOfSpaces <= 9 and
      next(module.hotkeys.modifiers) and
      next(module.navigationHotkeyModifiers) then
    for i = 1, module.numberOfSpaces do
      bindings[i] = hs.hotkey.bind(module.hotkeys.modifiers, tostring(i), function()
        local focusedWindow = getFocusedWindowAndScreen()
        if focusedWindow then
          moveWindowToSpace(focusedWindow, i)
        end
      end)
    end
    if module.hotkeys.previousSpaceKey and module.hotkeys.previousSpaceKey ~= "" then
      bindings.previous = hs.hotkey.bind(
        module.hotkeys.modifiers,
        module.hotkeys.previousSpaceKey,
        moveWindowToPreviousSpace
      )
    end
    if module.hotkeys.nextSpaceKey and module.hotkeys.nextSpaceKey ~= "" then
      bindings.next = hs.hotkey.bind(
        module.hotkeys.modifiers,
        module.hotkeys.nextSpaceKey,
        moveWindowToNextSpace
      )
    end
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
