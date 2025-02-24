module = {}

module.display = ""
module.numberOfSpaces = 0
module.hotkeys = {
  modifiers = {},
  previousSpaceKey = "",
  nextSpaceKey = ""
}
module.navigationHotkeyModifiers = {}

local bindings = {}

local function getFocusedWindowAndScreen()
  local focusedWindow = hs.window.focusedWindow()
  local screen = focusedWindow:screen()
  if not focusedWindow or screen:name() ~= module.display then
    return
  end

  return focusedWindow, screen
end

local function getCurrentSpaceNumber(screen)
  local spacesData = hs.spaces.data_managedDisplaySpaces()
  if not spacesData then
    return nil
  end

  local targetScreen
  for _, display in ipairs(spacesData) do
    if display["Display Identifier"] == screen:getUUID() then
      targetScreen = display
      break
    end
  end

  if not targetScreen then
    return nil
  end

  local currentSpaceId = targetScreen["Current Space"].ManagedSpaceID
  for i, space in ipairs(targetScreen.Spaces) do
    if space.ManagedSpaceID == currentSpaceId then
      return i
    end
  end

  return nil
end

local function moveToSpace(window, spaceNumber)
  local frame = window:frame()
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseDown, { x = frame.x + 5, y = frame.y + 20 }):post()
  hs.eventtap.keyStroke(module.navigationHotkeyModifiers, tostring(spaceNumber))
  hs.timer.usleep(100000)
  hs.eventtap.event.newMouseEvent(hs.eventtap.event.types.leftMouseUp, { x = frame.x + 5, y = frame.y + 20 }):post()
end

local function moveToPreviousSpace()
  local window, screen = getFocusedWindowAndScreen()
  if not screen then
    return
  end

  local currentSpaceNumber = getCurrentSpaceNumber(screen)
  if currentSpaceNumber then
    moveToSpace(window, (currentSpaceNumber % module.numberOfSpaces) + 1)
  end
end

local function moveToNextSpace()
  local window, screen = getFocusedWindowAndScreen()
  if not screen then
    return
  end

  local currentSpaceNumber = getCurrentSpaceNumber(screen)
  if currentSpaceNumber then
    moveToSpace(window, ((currentSpaceNumber - 2 + module.numberOfSpaces) % module.numberOfSpaces) + 1)
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
          moveToSpace(focusedWindow, i)
        end
      end)
    end

    if module.hotkeys.previousSpaceKey and module.hotkeys.previousSpaceKey ~= "" and
        module.hotkeys.nextSpaceKey and module.hotkeys.nextSpaceKey ~= "" then
      bindings.previous = hs.hotkey.bind(module.hotkeys.modifiers, module.hotkeys.previousSpaceKey, moveToPreviousSpace)
      bindings.next = hs.hotkey.bind(module.hotkeys.modifiers, module.hotkeys.nextSpaceKey, moveToNextSpace)
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
