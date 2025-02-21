local module = {}

module.ignoreWindowTitles = {
  "Activity Monitor",
}
module.titleMaxLength = 50
module.titlePatternsToRemove = {
  " – Audio playing$",
  " - High memory usage - .*$",
  " – Camera recording$",
  " – Microphone recording$",
  " – Camera and microphone recording$",
}

local appWatcher = nil
local windowFilter = nil
local currentTitle = nil

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

  for _, ignoredApp in ipairs(module.ignoreWindowTitles) do
    if appName == ignoredApp then
      return bundleId, appName
    end
  end

  local title = app:mainWindow():title()

  -- Remove app name from end of title
  title = title:gsub("%s*[-–—]%s*" .. appName .. "$", "")

  -- Remove additional patterns
  for _, pattern in ipairs(module.titlePatternsToRemove) do
    title = title:gsub(pattern, "")
  end

  -- Truncate to max length
  local truncated = false

  if #title > module.titleMaxLength then
    title = string.sub(title, 1, module.titleMaxLength)
    truncated = true
  end

  -- Remove trailing whitespaces
  title = title:gsub("%s+$", "")

  -- Add ellipsis if truncated
  if truncated then
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

  handleWindowChange()
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
