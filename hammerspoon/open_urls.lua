local module = {}
local binding

module.hotkey = {}

local function openURLs()
  local originalData = hs.pasteboard.readAllData()
  hs.timer.usleep(100000)
  hs.eventtap.keyStroke({ "cmd" }, "c")
  hs.timer.usleep(100000)
  local selectedText = hs.pasteboard.readString()
  hs.timer.doAfter(0.1, function()
    hs.pasteboard.writeAllData(originalData)
  end)
  if not selectedText then
    return
  end

  local urlCommands = ""
  for url in string.gmatch(selectedText, "(https?://[^%s]+)") do -- Need a better pattern
    urlCommands = urlCommands .. string.format('make new tab with properties {URL:"%s"}\n', url)
  end
  if urlCommands == "" then
    return
  end
  hs.osascript.applescript(string.format([[
    tell application "Google Chrome"
      set activeIndex to get active tab index of window 1
      tell window 1
        %s
      end tell
      set active tab index of window 1 to activeIndex
    end tell
  ]], urlCommands))
end

function module.init()
  if next(module.hotkey) then
    binding = hs.hotkey.bind(module.hotkey.modifiers, module.hotkey.key, openURLs)
  end
end

function module.cleanup()
  if binding then
    binding:delete()
    binding = nil
  end
end

return module
