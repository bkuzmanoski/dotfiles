local module = {}
local allModifiers = { "cmd", "alt", "shift", "ctrl", "fn", "capslock" }
local keyboardTap, mouseTap, activeWindow, activeOperation

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
  local mousePosition = hs.geometry.new(hs.mouse.absolutePosition())
  local windows = hs.window.filter.new():setOverrideFilter({
    allowRoles = { "AXStandardWindow" },
    fullscreen = false,
    visible = true
  }):getWindows()
  for _, window in ipairs(windows) do
    if mousePosition:inside(window:frame()) then
      return window
    end
  end
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
