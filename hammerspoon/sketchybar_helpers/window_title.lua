local module = {}

module.ignoreApps = {}
module.maxLength = 0
module.patternsToRemove = {}

local appWatcher, windowFilter, currentTitle

local utils = require("utils")

local function getWindowDetails()
  local app = hs.application.frontmostApplication()

  if not app then
    return nil, nil
  end

  local bundleId = app:bundleID()
  local appName = app:name()
  local mainWindow = app:mainWindow()

  if not mainWindow then
    return bundleId, appName
  end

  -- Fallback to app name if app is in the ignore list
  for _, ignoredApp in ipairs(module.ignoreApps) do
    if appName == ignoredApp then
      return bundleId, appName
    end
  end

  local title = app:mainWindow():title()

  -- Remove app name from end of title
  title = title:gsub("%s*[-–—]%s*" .. utils.escapeString(appName) .. "$", "")

  -- Remove additional patterns
  for _, pattern in ipairs(module.patternsToRemove) do
    title = title:gsub(pattern, "")
  end

  -- Truncate to max length
  local truncationOffset = utf8.offset(title, module.maxLength)
  if module.maxLength > 0 and truncationOffset then
    title = string.sub(title, 1, truncationOffset)
  end

  -- Remove trailing whitespaces
  title = title:gsub("%s+$", "")

  -- Add ellipsis if truncated
  if module.maxLength > 0 and truncationOffset then
    title = title .. "…"
  end

  -- If title is empty return app name
  if title == "" then
    return bundleId, appName
  end

  return bundleId, title
end

local function handleWindowChange()
  local bundleId, newTitle = getWindowDetails()

  if newTitle and newTitle ~= currentTitle then
    currentTitle = newTitle
    local escapedTitle = newTitle:gsub('"', '\\"')
    hs.execute(
      "/opt/homebrew/bin/sketchybar --trigger window_change BUNDLE_ID=\"" ..
      bundleId .. "\" TITLE=\"" .. escapedTitle .. "\"", false
    )
  end
end

function module.init()
  windowFilter = hs.window.filter.new()
  windowFilter:subscribe(hs.window.filter.windowCreated, handleWindowChange)
  windowFilter:subscribe(hs.window.filter.windowDestroyed, handleWindowChange)
  windowFilter:subscribe(hs.window.filter.windowFocused, handleWindowChange)
  windowFilter:subscribe(hs.window.filter.windowUnfocused, handleWindowChange)
  windowFilter:subscribe(hs.window.filter.windowTitleChanged, handleWindowChange)

  appWatcher = hs.application.watcher.new(function(_, eventType, _)
    if eventType == hs.application.watcher.launched or eventType == hs.application.watcher.terminated then
      handleWindowChange()
    end
  end)
  appWatcher:start()
end

function module.cleanup()
  if windowFilter then
    windowFilter:unsubscribeAll()
    windowFilter = nil
  end

  if appWatcher then
    appWatcher:stop()
    appWatcher = nil
  end
end

return module
