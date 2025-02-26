local utils = require("utils")
local module = {}
local bindings = {}

module.hotkeys = {
  left = {},
  right = {}
}

local function focusWindow(direction)
  local focusedWindow = hs.window.focusedWindow()
  if not focusedWindow then return end

  local screen = focusedWindow:screen()
  local screenFrame = focusedWindow:frame()
  local screenCenter = screenFrame.x + screenFrame.w / 2
  local candidate, candidateCenter

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

  if not candidate then
    utils.playAlert()
    return
  end

  candidate:focus()
end

function module.init()
  if next(module.hotkeys.left) then
    bindings.left = hs.hotkey.bind(module.hotkeys.left.modifiers, module.hotkeys.left.key, function()
      focusWindow("left")
    end)
  end
  if next(module.hotkeys.right) then
    bindings.right = hs.hotkey.bind(module.hotkeys.right.modifiers, module.hotkeys.right.key,
      function()
        focusWindow("right")
      end)
  end
end

function module.cleanup()
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
