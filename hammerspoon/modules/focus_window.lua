local module = {}
local bindings = {}
local windowFilter

local function focusWindow(direction)
  local screen = hs.mouse.getCurrentScreen()
  local focusedWindow = hs.window.focusedWindow()
  local otherWindows = hs.fnutils.filter(windowFilter:getWindows(), function(window)
    return window:screen() == screen and window ~= focusedWindow
  end)

  if direction == "frontmost" or not focusedWindow or focusedWindow:screen() ~= screen then
    if #otherWindows > 0 then otherWindows[1]:focus() end
    return
  end

  local focusedWindowFrame = focusedWindow:frame()
  local leftWindows = {}
  local rightWindows = {}

  for _, window in ipairs(otherWindows) do
    local frame = window:frame()
    if frame.x + (frame.w / 2) < focusedWindowFrame.x + (focusedWindowFrame.w / 2) then
      table.insert(leftWindows, window)
    else
      table.insert(rightWindows, window)
    end
  end

  local function sortWindowsRightToLeft(a, b)
    return (a:frame().x + (a:frame().w / 2)) > (b:frame().x + (b:frame().w / 2))
  end

  local function sortWindowsLeftToRight(a, b)
    return (a:frame().x + (a:frame().w / 2)) < (b:frame().x + (b:frame().w / 2))
  end

  if direction == "left" then
    if #leftWindows > 0 then
      table.sort(leftWindows, sortWindowsRightToLeft)
      leftWindows[1]:focus()
    elseif #rightWindows > 0 then
      table.sort(rightWindows, sortWindowsRightToLeft)
      rightWindows[1]:focus()
    end
  elseif direction == "right" then
    if #rightWindows > 0 then
      table.sort(rightWindows, sortWindowsLeftToRight)
      rightWindows[1]:focus()
    elseif #leftWindows > 0 then
      table.sort(leftWindows, sortWindowsLeftToRight)
      leftWindows[1]:focus()
    end
  end
end

function module.init(config)
  if next(bindings) or windowFilter then module.cleanup() end

  if config then
    local handlers = {
      focusFrontmost = function() focusWindow("frontmost") end,
      focusLeft = function() focusWindow("left") end,
      focusRight = function() focusWindow("right") end
    }
    for action, hotkey in pairs(config) do
      if hotkey.modifiers and hotkey.key and handlers[action] then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action], nil, handlers[action])
      end
    end

    if next(bindings) then
      windowFilter = hs.window.filter.new()
          :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, allowTitles = ".", currentSpace = true, fullscreen = false, visible = true })
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}

  windowFilter = nil
end

return module
