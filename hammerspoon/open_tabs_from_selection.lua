local module = {}
local binding

module.hotkey = {
  urls = {},
  search = {}
}

local function getSelectedText()
  local originalData = hs.pasteboard.readAllData()
  hs.timer.usleep(100000)
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  hs.timer.usleep(100000)
  local selectedText = hs.pasteboard.readString()
  hs.timer.doAfter(0.1, function() hs.pasteboard.writeAllData(originalData) end)

  if not selectedText then
    return
  end

  return selectedText
end

local function openTabs(applescriptFragment)
  local focusedWindow = hs.window.focusedWindow()

  hs.osascript.applescript(string.format([[
    tell application "Google Chrome"
      set activeIndex to get active tab index of window 1
      tell window 1
        %s
      end tell
      set active tab index of window 1 to activeIndex
    end tell
  ]], applescriptFragment))

  if focusedWindow and focusedWindow:application():name() ~= "Google Chrome" then
    hs.timer.usleep(500000)
    focusedWindow:focus()
  end
end

local function openURLs()
  local selectedText = getSelectedText()
  if not selectedText then
    return
  end

  local urlCommands = ""
  for url in string.gmatch(selectedText, "(https?://[^%s]+)") do
    urlCommands = urlCommands .. string.format('make new tab with properties {URL:"%s"}\n', url)
  end

  if urlCommands == "" then
    return
  end

  openTabs(urlCommands)
end

local function searchForSelection()
  local selectedText = getSelectedText()
  if not selectedText then
    return
  end

  local searchURL = "https://www.google.com/search?q=" .. hs.http.encodeForQuery(selectedText)
  openTabs(string.format('make new tab with properties {URL:"%s"}\n', searchURL))
end

function module.init()
  if next(module.hotkey.urls) then
    binding = hs.hotkey.bind(module.hotkey.urls.modifiers, module.hotkey.urls.key, openURLs)
  end
  if next(module.hotkey.search) then
    binding = hs.hotkey.bind(module.hotkey.search.modifiers, module.hotkey.search.key, searchForSelection)
  end
end

function module.cleanup()
  if binding then
    binding:delete()
    binding = nil
  end
end

return module
