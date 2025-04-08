local utils = require("utils")

local module = {}
local bindings = {}

local function getSelectedText()
  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focusedElement then return nil end

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

local function openSelectedUrls()
  local selectedText = getSelectedText()
  if not selectedText or selectedText == "" then
    utils.playAlert()
    return
  end

  local success = false
  local urls = {}
  local task = hs.task.new(
    hs.configdir .. "/helpers/bin/ExtractURLs",
    function(exitCode, stdOut)
      success = exitCode == 0
      for url in stdOut:gmatch("([^\n]+)") do table.insert(urls, url) end
    end
  )
  task:setInput(selectedText):start():waitUntilExit()

  if not success then
    utils.playAlert()
    return
  end

  local urlCommands = ""
  for _, url in ipairs(urls) do
    urlCommands = urlCommands .. string.format('make new tab with properties {URL:"%s"}\n', url)
  end

  if urlCommands == "" then
    utils.playAlert()
    return
  end

  openTabs(urlCommands)
end

local function searchForSelection()
  local selectedText = getSelectedText()
  if not selectedText or selectedText == "" then
    utils.playAlert()
    return
  end

  local searchUrl = "https://www.google.com/search?q=" .. hs.http.encodeForQuery(selectedText)
  openTabs(string.format('make new tab with properties {URL:"%s"}\n', searchUrl))
end

function module.init(config)
  if next(bindings) then module.cleanup() end

  if config then
    local handlers = { openSelectedUrls = openSelectedUrls, searchForSelection = searchForSelection }
    for action, hotkey in pairs(config) do
      if handlers[action] and hotkey.modifiers and hotkey.key then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
      end
    end
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}
end

return module
