local module = {}
local allModifiers = { "cmd", "alt", "shift", "ctrl", "fn", "capslock" }
local windowFilter, keyboardTap, mouseTap, activeWindow, activeOperation

module.modifiers = {
  move = {},
  resize = {}
}

local function exactModifiersMatch(requiredModifiers, flags)
  local requiredLookup = {}
  for _, modifier in ipairs(requiredModifiers) do
    requiredLookup[modifier] = true
  end

  for _, modifier in ipairs(allModifiers) do
    if (requiredLookup[modifier] and not flags[modifier]) or
        (not requiredLookup[modifier] and flags[modifier]) then
      return false
    end
  end

  return true
end

local function getWindowUnderMouse()
  local rawMousePosition = hs.mouse.absolutePosition()
  local topmostElement = hs.axuielement.systemWideElement():elementAtPosition(rawMousePosition)

  -- Get window of topmost element under mouse
  local window = topmostElement:attributeValue("AXWindow"):asHSWindow()
  if window and window:subrole() == "AXStandardWindow" then
    return window
  end

  -- If no window was found (e.g. it is a system dialog, etc.), fall back to the frontmost window under the mouse
  local orderedWindows = windowFilter:getWindows()
  local mousePosition = hs.geometry.new(rawMousePosition)
  for _, candidateWindow in ipairs(orderedWindows) do
    if mousePosition:inside(candidateWindow:frame()) then
      return candidateWindow
    end
  end

  return nil
end

local function startOperation(operationType)
  activeWindow = getWindowUnderMouse()
  if not activeWindow or (operationType == "resize" and not activeWindow:isMaximizable()) then
    return
  end

  activeOperation = operationType
  mouseTap:start()
end

local function stopOperation()
  activeWindow = nil
  activeOperation = nil
  if mouseTap then
    mouseTap:stop()
  end
end

local function handleFlagsChange(event)
  stopOperation()
  local flags = event:getFlags()
  if exactModifiersMatch(module.modifiers.move, flags) then
    startOperation("move")
  elseif exactModifiersMatch(module.modifiers.resize, flags) then
    startOperation("resize")
  end
end

local function handleMouseMove(event)
  if activeWindow then
    local frame = activeWindow:frame()
    if activeOperation == "move" then
      frame.x = frame.x + event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
      frame.y = frame.y + event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)
    elseif activeOperation == "resize" then
      frame.w = frame.w + event:getProperty(hs.eventtap.event.properties.mouseEventDeltaX)
      frame.h = frame.h + event:getProperty(hs.eventtap.event.properties.mouseEventDeltaY)
    end
    activeWindow:setFrame(frame, 0)
  end
end

function module.init()
  windowFilter = hs.window.filter.new()
      :setOverrideFilter({
        allowRoles = { "AXStandardWindow" },
        currentSpace = true,
        fullscreen = false,
        visible = true
      })
  if #module.modifiers.move > 0 or #module.modifiers.resize > 0 then
    keyboardTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, handleFlagsChange)
    keyboardTap:start()
    mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, handleMouseMove)
  end
end

function module.cleanup()
  stopOperation()
  if keyboardTap then
    keyboardTap:stop()
    keyboardTap = nil
  end
  if mouseTap then
    mouseTap:stop()
    mouseTap = nil
  end
end

return module
