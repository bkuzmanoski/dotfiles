local module = {}

module.hotkeys = {
  left = { modifiers = { "option", "command" }, key = "[" },
  right = { modifiers = { "option", "command" }, key = "]" },
}

local leftHotkey, rightHotkey

function module.focusWindow(direction)
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow then return end

  local screen = focusedWindow:screen()
  local screenFrame = focusedWindow:frame()
  local screenCenter = screenFrame.x + screenFrame.w / 2

  local candidate = nil
  local candidateCenter = nil

  local windows = hs.window.orderedWindows()
  for _, window in ipairs(windows) do
    if window:id() ~= focusedWindow:id() and window:screen() == screen and window:isVisible() then
      local windowFrame = window:frame()
      local windowCenter = windowFrame.x + windowFrame.w / 2
      if direction == "left" and windowCenter < screenCenter then
        if not candidate or windowCenter > candidateCenter then
          candidate = window
          candidateCenter = windowCenter
        end
      elseif direction == "right" and windowCenter > screenCenter then
        if not candidate or windowCenter < candidateCenter then
          candidate = window
          candidateCenter = windowCenter
        end
      end
    end
  end

  if candidate then
    candidate:focus()
  end
end

function module.init()
  leftHotkey = hs.hotkey.bind(module.hotkeys.left.modifiers, module.hotkeys.left.key, function()
    module.focusWindow("left")
  end)
  rightHotkey = hs.hotkey.bind(module.hotkeys.right.modifiers, module.hotkeys.right.key, function()
    module.focusWindow("right")
  end)
end

function module.cleanup()
  if leftHotkey then
    leftHotkey:delete()
    leftHotkey = nil
  end
  if rightHotkey then
    rightHotkey:delete()
    rightHotkey = nil
  end
end

return module
