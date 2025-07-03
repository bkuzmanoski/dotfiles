local utils = require("utils")

local module = {}
local binding, mouseTap, debounceTimer

local validSubroles = {
  ["AXStandardWindow"] = true,
  ["AXDialog"] = true,
  ["AXSystemDialog"] = true,
  ["AXFloatingWindow"] = true,
  ["AXSystemFloatingWindow"] = true
}

local function focusWindowUnderMouse()
  local window = utils.getWindowUnderMouse(hs.window.orderedWindows(), validSubroles)
  if not window then return end

  local focusedWindow = hs.window.focusedWindow()
  if focusedWindow and focusedWindow == window then return end

  print("focussing")
  window:focus()
end

local function focusWindowUnderMouseDebounced()
  if debounceTimer then debounceTimer:stop() end
  debounceTimer = hs.timer.doAfter(0.1, focusWindowUnderMouse)
end

local function startMouseTap()
  mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, focusWindowUnderMouseDebounced):start()
end

local function stopMouseTap()
  if mouseTap then mouseTap:stop() end
  mouseTap = nil
end

function module.init(config)
  if binding or mouseTap then module.cleanup() end

  if not config or not config.toggleHotkey then return module end

  binding = hs.hotkey.bind(config.toggleHotkey.modifiers, config.toggleHotkey.key, function()
    if mouseTap then stopMouseTap() else startMouseTap() end
  end)

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
