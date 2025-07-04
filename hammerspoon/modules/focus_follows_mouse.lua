local utils = require("utils")

local module = {}
local windowCache = {}
local binding, mouseTap, debounceTimer, cacheTime, lastPosition
local playSoundOnToggle, guardApps, guardWindows

local validSubroles = {
  ["AXStandardWindow"] = true,
  ["AXDialog"] = true,
  ["AXSystemDialog"] = true,
  ["AXFloatingWindow"] = true,
  ["AXSystemFloatingWindow"] = true
}

local function getWindowsWithCache()
  local now = hs.timer.secondsSinceEpoch()
  if not cacheTime or now - cacheTime > 1 then
    windowCache = hs.window.orderedWindows()
    cacheTime = now
  end
  return windowCache
end

local function shouldGuardCurrentWindow(focusedWindow)
  if not focusedWindow then return false end

  local focusedApp = focusedWindow:application()
  if focusedApp and guardApps[focusedApp:name()] then return true end

  local focusedWindowTitle = focusedWindow:title()
  if focusedWindowTitle then
    for _, rule in ipairs(guardWindows) do
      if type(rule) == "string" then
        if focusedWindowTitle:match(rule) then return true end
      elseif type(rule) == "table" and rule.pattern then
        if focusedWindowTitle:match(rule.pattern) then
          if not rule.exclude or not focusedWindowTitle:match(rule.exclude) then
            return true
          end
        end
      end
    end
  end

  return false
end

local function focusWindowUnderMouse()
  local currentPosition = hs.mouse.absolutePosition()
  if lastPosition then
    local distance = math.sqrt((currentPosition.x - lastPosition.x) ^ 2 + (currentPosition.y - lastPosition.y) ^ 2)
    if distance < 16 then return end
  end

  lastPosition = currentPosition

  local windows = getWindowsWithCache()
  local windowToFocus = utils.getWindowUnderMouse(windows, validSubroles)
  if not windowToFocus then return end

  local focusedWindow = hs.window.focusedWindow()
  if focusedWindow == windowToFocus then return end

  if shouldGuardCurrentWindow(focusedWindow) then return end

  windowToFocus:focus()
end

local function focusWindowUnderMouseDebounced()
  if debounceTimer then debounceTimer:stop() end
  debounceTimer = hs.timer.doAfter(0.1, focusWindowUnderMouse)
end

local function startMouseTap()
  mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, focusWindowUnderMouseDebounced):start()
  if playSoundOnToggle then utils.playAlert(1, "Funk") end
end

local function stopMouseTap()
  if mouseTap then mouseTap:stop() end
  mouseTap = nil

  if playSoundOnToggle then utils.playAlert(1, "Bottle") end
end

function module.init(config)
  if binding or mouseTap then module.cleanup() end

  if not config then return module end

  playSoundOnToggle = config.playSoundOnToggle or true
  guardApps = {}
  for _, appName in ipairs(config.guardApps or {}) do
    guardApps[appName] = true
  end

  guardWindows = config.guardWindows or {}

  if config.toggleHotkey then
    binding = hs.hotkey.bind(config.toggleHotkey.modifiers, config.toggleHotkey.key, function()
      if mouseTap then stopMouseTap() else startMouseTap() end
    end)
  end

  if config.enableOnLoad then startMouseTap() end

  return module
end

function module.cleanup()
  if binding then binding:delete() end
  binding = nil

  stopMouseTap()

  if debounceTimer then debounceTimer:stop() end
  debounceTimer = nil
end

return module
