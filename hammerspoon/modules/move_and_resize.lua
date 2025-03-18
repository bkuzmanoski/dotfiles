local module = {}
local moveModifiers, resizeModifiers, windowFilter, keyboardTap, mouseTap, activeOperation, activeWindow

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
  if not activeWindow or (operationType == "resize" and not activeWindow:isMaximizable()) then return end
  activeOperation = operationType
  mouseTap:start()
end

local function stopOperation()
  if mouseTap then mouseTap:stop() end
  activeOperation = nil
  activeWindow = nil
end

local function handleFlagsChange(event)
  stopOperation()

  local flags = event:getFlags()
  if moveModifiers and flags:containExactly(moveModifiers) then
    startOperation("move")
    return
  end
  if resizeModifiers and flags:containExactly(resizeModifiers) then
    startOperation("resize")
    return
  end
end

local function handleMouseMove(event)
  if activeOperation and activeWindow then
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

function module.init(config)
  if keyboardTap or mouseTap then module.cleanup() end

  if config and (config.moveModifiers or config.resizeModifiers) then
    moveModifiers = config.moveModifiers
    resizeModifiers = config.resizeModifiers

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

  return module
end

function module.cleanup()
  stopOperation()

  if keyboardTap then keyboardTap:stop() end
  keyboardTap = nil

  if mouseTap then mouseTap:stop() end
  mouseTap = nil
end

return module
