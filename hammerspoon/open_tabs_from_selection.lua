local module = {}
local binding

module.hotkey = {
  urls = {},
  search = {}
}

local function getSelectedText()
  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focusedElement then
    return
  end

  return focusedElement:attributeValue("AXSelectedText")
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

local function extractURLs()
  local selectedText = getSelectedText()
  if not selectedText or selectedText == "" then
    return
  end

  local success = false
  local urls = {}
  local task = hs.task.new(
    hs.configdir .. "/helpers/bin/ExtractURLs",
    function(exitCode, stdOut)
      success = exitCode == 0
      for url in stdOut:gmatch("([^\n]+)") do
        table.insert(urls, url)
      end
    end
  )
  task:setInput(selectedText):start():waitUntilExit()

  if not success then
    return
  end

  local urlCommands = ""
  for _, url in ipairs(urls) do
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
  if next(module.hotkey.extractURLs) then
    binding = hs.hotkey.bind(module.hotkey.extractURLs.modifiers, module.hotkey.extractURLs.key, extractURLs)
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
