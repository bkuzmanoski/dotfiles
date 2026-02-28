local module = {}

local LEFT_COMMAND_BIT = 0x08
local RIGHT_COMMAND_BIT = 0x10
local BASE_FLAGS = 0x00a00100
local CONTROL_FLAGS = 0x00040001
local ALT_FLAGS = 0x00080020
local SHIFT_FLAGS = 0x00020002
local COMMAND_FLAGS = 0x00100008

local keymap, eventTap, eventTapWatchdog
local activeHotkeys = {}

local function handleKeyEvent(event)
  local keyCode = event:getKeyCode()
  local hotkey = keymap[hs.keycodes.map[keyCode]]

  if not hotkey then
    return false
  end

  local rawFlags = event:rawFlags()
  local isDown = (event:getType() == hs.eventtap.event.types.keyDown)
  local isRightCommand = (rawFlags & RIGHT_COMMAND_BIT) ~= 0

  if not isDown and activeHotkeys[keyCode] then
    hotkey = activeHotkeys[keyCode]
    activeHotkeys[keyCode] = nil
  else
    if not isRightCommand or not hotkey then
      return false
    end

    if isDown then
      activeHotkeys[keyCode] = hotkey
    end
  end

  local isLeftCommand = (rawFlags & LEFT_COMMAND_BIT) ~= 0
  local modifiers = event:getFlags()
  local passthroughModifiers = {}
  local targetFlags = BASE_FLAGS

  if modifiers["ctrl"] then
    table.insert(passthroughModifiers, "ctrl")
    targetFlags = targetFlags | CONTROL_FLAGS
  end

  if modifiers["alt"] then
    table.insert(passthroughModifiers, "alt")
    targetFlags = targetFlags | ALT_FLAGS
  end

  if modifiers["shift"] then
    table.insert(passthroughModifiers, "shift")
    targetFlags = targetFlags | SHIFT_FLAGS
  end

  if isLeftCommand then
    table.insert(passthroughModifiers, "cmd")
    targetFlags = targetFlags | COMMAND_FLAGS
  end

  hs.eventtap.event.newKeyEvent(passthroughModifiers, hotkey, isDown):rawFlags(targetFlags):post()

  return true
end

local function restartEventTapIfNeeded()
  if eventTap and not eventTap:isEnabled() then
    eventTap:start()
  end
end

function module.init(config)
  if eventTap then
    module.cleanup()
  end

  if not config or not config.keymap then
    return module
  end

  keymap = config.keymap
  eventTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown, hs.eventtap.event.types.keyUp }, handleKeyEvent):start()
  eventTapWatchdog = hs.timer.doEvery(3, restartEventTapIfNeeded)

  return module
end

function module.cleanup()
  if eventTap then
    eventTap:stop()
  end

  eventTap = nil

  if eventTapWatchdog then
    eventTapWatchdog:stop()
  end

  eventTapWatchdog = nil
end

return module
