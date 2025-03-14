local module = {}
local windowFilter, keyboardTap, mouseTap, activeWindow, activeOperation

module.modifiers = {
  move = {},
  resize = {}
}

local function getWindowUnderMouse()
  local rawMousePosition = hs.mouse.absolutePosition()

  -- Get window of topmost element under mouse
  local rawWindow = hs.axuielement.systemWideElement():elementAtPosition(rawMousePosition):attributeValue("AXWindow")
  if rawWindow and rawWindow:attributeValue("AXSubrole") == "AXStandardWindow" then
    return rawWindow:asHSWindow()
  end

  -- If topmost element is not (or not in) an AXStandardWindow, fall back to the frontmost window under the mouse
  local orderedWindows = windowFilter:getWindows()
  local mousePosition = hs.geometry.new(rawMousePosition)
  for _, window in ipairs(orderedWindows) do
    if mousePosition:inside(window:frame()) then
      return window
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
  if flags:containExactly(module.modifiers.move) then
    startOperation("move")
  elseif flags:containExactly(module.modifiers.resize) then
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
  if #module.modifiers.move > 0 or #module.modifiers.resize > 0 then
    windowFilter = hs.window.filter.new()
        :setOverrideFilter({
          allowRoles = { "AXStandardWindow" },
          currentSpace = true,
          fullscreen = false,
          visible = true
        })
    keyboardTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, handleFlagsChange):start()
    mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, handleMouseMove) -- Don't start yet
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
