local utils = require("utils")

local module = {}
local bindings = {}
local tiledSpaces = {}
local screenWatcher, applicationWatcher, windowFilter, debounceTimer
local topOffset, padding, splitRatios, initialNumberOfStackedWindows, excludedApps

local edge = { left = "left", right = "right", top = "top", bottom = "bottom" }

local function getOppositeEdge(initialEdge)
  local opposites = {
    [edge.left] = edge.right,
    [edge.right] = edge.left,
    [edge.top] = edge.bottom,
    [edge.bottom] = edge.top
  }

  return opposites[initialEdge]
end

local function getCurrentScreenAndSpace()
  local screen = hs.screen.mainScreen()
  if not screen then return nil, nil end

  local activeSpaceID = hs.spaces.activeSpaceOnScreen(screen)
  if not activeSpaceID then return nil, nil end

  return screen, activeSpaceID
end

local function getCurrentWindowData(screen, spaceID)
  local windowData = {}
  hs.fnutils.ieach(hs.window._orderedwinids(), function(id)
    local window = hs.window.get(id)
    if window then
      local app = window:application()
      local windowSpaces = hs.spaces.windowSpaces(window)
      if app and not excludedApps[app:name()] and
          window:screen() == screen and
          #windowSpaces == 1 and
          hs.fnutils.contains(windowSpaces, spaceID) and
          window:isVisible() and
          window:isStandard() and
          window:isMaximizable() and
          not window:isFullScreen() then
        table.insert(windowData, { id = id, window = window })
      end
    end
  end)

  return windowData
end

local function dividedRect(rect, ratio, mainEdge, margin)
  local mainRect = hs.geometry.copy(rect)
  local stackRect = hs.geometry.copy(rect)

  if mainEdge == edge.left then
    mainRect.w = math.floor(rect.w * ratio)
    stackRect.x = mainRect.x + mainRect.w + margin
    stackRect.w = rect.w - mainRect.w - margin
  elseif mainEdge == edge.right then
    stackRect.w = math.floor(rect.w * (1 - ratio))
    mainRect.x = stackRect.x + stackRect.w + margin
    mainRect.w = rect.w - stackRect.w - margin
  elseif mainEdge == edge.top then
    mainRect.h = math.floor(rect.h * ratio)
    stackRect.y = mainRect.y + mainRect.h + margin
    stackRect.h = rect.h - mainRect.h - margin
  elseif mainEdge == edge.bottom then
    stackRect.h = math.floor(rect.h * (1 - ratio))
    mainRect.y = stackRect.y + stackRect.h + margin
    mainRect.h = rect.h - stackRect.h - margin
  end

  return mainRect, stackRect
end

local function layoutStackWindows(windows, boundingRect, margin, isHorizontal)
  local windowCount = #windows
  if windowCount == 0 then return {} end

  local windowWidth, windowHeight
  if isHorizontal then
    windowWidth = math.floor((boundingRect.w - (margin * (windowCount - 1))) / windowCount)
    windowHeight = boundingRect.h
  else
    windowWidth = boundingRect.w
    windowHeight = math.floor((boundingRect.h - (margin * (windowCount - 1))) / windowCount)
  end

  local windowFrames = {}
  for i, window in ipairs(windows) do
    local xOffset = isHorizontal and (i - 1) * (windowWidth + margin) or 0
    local yOffset = isHorizontal and 0 or (i - 1) * (windowHeight + margin)
    local frame = { x = boundingRect.x + xOffset, y = boundingRect.y + yOffset, w = windowWidth, h = windowHeight }
    table.insert(windowFrames, { window = window, frame = frame })
  end

  return windowFrames
end

local function setFrameWithConstraints(window, targetFrame, screenBounds)
  local currentFrame = window:frame()
  if hs.geometry.equals(currentFrame, targetFrame) then return end

  window:setFrame(targetFrame)

  local resultingFrame = window:frame()
  local needsRepositioning = false
  if resultingFrame.x + resultingFrame.w > screenBounds.x + screenBounds.w then
    resultingFrame.x = screenBounds.x + screenBounds.w - resultingFrame.w
    needsRepositioning = true
  end

  if resultingFrame.y + resultingFrame.h > screenBounds.y + screenBounds.h then
    resultingFrame.y = screenBounds.y + screenBounds.h - resultingFrame.h
    needsRepositioning = true
  end

  if needsRepositioning then
    window:setFrame(resultingFrame)
  end
end

local function applyLayout(screen, tilingState)
  local screenFrame = utils.getAdjustedScreenFrame(screen, topOffset, padding)
  local managedWindows = tilingState.managedWindows
  if #managedWindows == 0 then return end

  local newWindowStates = {}
  if #managedWindows == 1 or tilingState.numberOfStackedWindows == 0 then
    table.insert(newWindowStates, { window = managedWindows[1].window, frame = screenFrame })
  else
    local mainWindowFrame, stackBoundingRect =
        dividedRect(screenFrame, tilingState.splitRatio, tilingState.mainWindowEdge, padding)
    table.insert(newWindowStates, { window = managedWindows[1].window, frame = mainWindowFrame })

    local stackWindows = {}
    local endIndex = math.min(tilingState.numberOfStackedWindows + 1, #managedWindows)
    for i = 2, endIndex do
      table.insert(stackWindows, managedWindows[i].window)
    end

    if #stackWindows > 0 then
      local isHorizontal = tilingState.mainWindowEdge == edge.top or tilingState.mainWindowEdge == edge.bottom
      local stackFrames = layoutStackWindows(stackWindows, stackBoundingRect, padding, isHorizontal)
      hs.fnutils.each(stackFrames, function(stackFrame)
        table.insert(newWindowStates, stackFrame)
      end)
    end
  end

  hs.fnutils.each(newWindowStates, function(windowState)
    setFrameWithConstraints(windowState.window, windowState.frame, screenFrame)
  end)

  for i = #newWindowStates + 1, #managedWindows do
    local windowData = managedWindows[i]
    windowData.window:setFrame(windowData.originalFrame)
  end
end


local function restoreAllWindows(spaceID)
  local tilingState = tiledSpaces[spaceID]
  if not tilingState then return end

  for _, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window and windowData.originalFrame then
      windowData.window:setFrame(windowData.originalFrame)
    end
  end
end

local function updateManagedWindows()
  local screen, spaceID = getCurrentScreenAndSpace()
  if not screen or not spaceID then return end

  local tilingState = tiledSpaces[spaceID]
  if not tilingState then return end

  local currentWindowData = getCurrentWindowData(screen, spaceID)
  if #currentWindowData == 0 then
    restoreAllWindows(spaceID)
    tiledSpaces[spaceID] = nil
    return
  end

  local currentWindowsMap = {}
  for _, windowData in ipairs(currentWindowData) do
    currentWindowsMap[windowData.id] = windowData.window
  end

  local retainedWindows = {}
  for _, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window and currentWindowsMap[windowData.window:id()] then
      table.insert(retainedWindows, windowData)
    end
  end

  local existingWindowIds = {}
  for _, windowData in ipairs(retainedWindows) do
    existingWindowIds[windowData.window:id()] = true
  end

  local newWindows = {}
  for _, windowData in ipairs(currentWindowData) do
    if not existingWindowIds[windowData.id] then
      table.insert(newWindows, {
        window = windowData.window,
        originalFrame = windowData.window:frame()
      })
    end
  end

  tilingState.managedWindows = hs.fnutils.concat(retainedWindows, newWindows)

  local tiledWindowCount = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
  for i = tiledWindowCount + 1, #tilingState.managedWindows do
    local windowData = tilingState.managedWindows[i]
    windowData.originalFrame = windowData.window:frame()
  end

  tiledSpaces[spaceID] = tilingState
  applyLayout(screen, tilingState)
end

local function updateManagedWindowsDebounced()
  if debounceTimer then debounceTimer:stop() end
  debounceTimer = hs.timer.doAfter(0.3, updateManagedWindows)
end

local function updateTiledSpaces()
  local currentScreenIds = {}
  for _, screen in ipairs(hs.screen.allScreens()) do
    currentScreenIds[screen:id()] = true
  end

  for spaceID, tilingState in pairs(tiledSpaces) do
    local screenId = tilingState.screen:id()
    if not screenId or not currentScreenIds[screenId] then
      restoreAllWindows(spaceID)
      tiledSpaces[spaceID] = nil
    end
  end
end

local function tile(mainWindowEdge)
  local screen, spaceID = getCurrentScreenAndSpace()
  if not screen or not spaceID then return end

  local tilingState = tiledSpaces[spaceID]
  if tilingState then
    if tilingState.mainWindowEdge == mainWindowEdge then
      tilingState.splitRatio = utils.cycleNext(splitRatios, tilingState.splitRatio)
    else
      tilingState.mainWindowEdge = mainWindowEdge
      if getOppositeEdge(tilingState.mainWindowEdge) ~= mainWindowEdge then
        tilingState.splitRatio = utils.cycleNext(splitRatios)
      end
    end

    tiledSpaces[spaceID] = tilingState
    applyLayout(screen, tilingState)
  else
    local currentWindowData = getCurrentWindowData(screen, spaceID)
    if #currentWindowData == 0 then return end

    local managedWindows = {}
    for _, windowData in ipairs(currentWindowData) do
      table.insert(managedWindows, {
        window = windowData.window,
        originalFrame = windowData.window:frame()
      })
    end

    local newTilingState = {
      screen = screen,
      splitRatio = splitRatios[1],
      mainWindowEdge = mainWindowEdge,
      numberOfStackedWindows = initialNumberOfStackedWindows,
      managedWindows = managedWindows
    }

    tiledSpaces[spaceID] = newTilingState
    applyLayout(screen, newTilingState)
  end
end

local function updateStackSize(amount)
  local screen, spaceID = getCurrentScreenAndSpace()
  if not screen or not spaceID then return end

  local tilingState = tiledSpaces[spaceID]
  if not tilingState or #tilingState.managedWindows <= 1 then return end

  tilingState.numberOfStackedWindows = math.max(0,
    math.min(#tilingState.managedWindows - 1, tilingState.numberOfStackedWindows + amount))

  tiledSpaces[spaceID] = tilingState
  applyLayout(screen, tilingState)
end

local function promoteToMain()
  local window = hs.window.frontmostWindow()
  if not window then return end

  local screen, spaceID = getCurrentScreenAndSpace()
  if not screen or not spaceID then return end

  local tilingState = tiledSpaces[spaceID]
  if not tilingState or #tilingState.managedWindows == 0 then return end

  for i, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window:id() == window:id() then
      table.remove(tilingState.managedWindows, i)
      table.insert(tilingState.managedWindows, 1, windowData)
      tiledSpaces[spaceID] = tilingState
      applyLayout(screen, tilingState)
      return
    end
  end
end

local function promoteWindow()
  local window = hs.window.frontmostWindow()
  if not window then return end

  local screen, spaceID = getCurrentScreenAndSpace()
  if not screen or not spaceID then return end

  local tilingState = tiledSpaces[spaceID]
  if not tilingState or #tilingState.managedWindows <= 1 then return end

  local stackEnd = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
  for i, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window:id() == window:id() then
      if i == 1 then return end

      local windowToPromote = table.remove(tilingState.managedWindows, i)
      if i > stackEnd then
        table.insert(tilingState.managedWindows, stackEnd, windowToPromote)
      else
        table.insert(tilingState.managedWindows, i - 1, windowToPromote)
      end

      tiledSpaces[spaceID] = tilingState
      applyLayout(screen, tilingState)
      return
    end
  end
end

local function demoteWindow()
  local window = hs.window.frontmostWindow()
  if not window then return end

  local screen, spaceID = getCurrentScreenAndSpace()
  if not screen or not spaceID then return end

  local tilingState = tiledSpaces[spaceID]
  if not tilingState or #tilingState.managedWindows <= 1 then return end

  local stackEnd = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
  for i, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window:id() == window:id() then
      if i > stackEnd or i == #tilingState.managedWindows then return end

      local windowToDemote = table.remove(tilingState.managedWindows, i)
      table.insert(tilingState.managedWindows, i + 1, windowToDemote)
      tiledSpaces[spaceID] = tilingState
      applyLayout(screen, tilingState)
      return
    end
  end
end

local function floatWindow()
  local window = hs.window.frontmostWindow()
  if not window then return end

  local screen, spaceID = getCurrentScreenAndSpace()
  if not screen or not spaceID then return end

  local tilingState = tiledSpaces[spaceID]
  if not tilingState or #tilingState.managedWindows <= 1 then return end

  local stackEnd = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
  for i, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window:id() == window:id() then
      if i > stackEnd then return end

      local windowToFloat = table.remove(tilingState.managedWindows, i)
      table.insert(tilingState.managedWindows, windowToFloat)
      tiledSpaces[spaceID] = tilingState
      applyLayout(screen, tilingState)
      return
    end
  end
end

local function stopTiling()
  local _, spaceID = getCurrentScreenAndSpace()
  if not spaceID then return end

  restoreAllWindows(spaceID)
  tiledSpaces[spaceID] = nil
end

function module.init(config)
  if next(bindings) or windowFilter then module.cleanup() end

  if not config or not config.hotkeys then return module end

  local handlers = {
    tileLeft = function() tile(edge.left) end,
    tileRight = function() tile(edge.right) end,
    tileTop = function() tile(edge.top) end,
    tileBottom = function() tile(edge.bottom) end,
    increaseStackSize = function() updateStackSize(1) end,
    decreaseStackSize = function() updateStackSize(-1) end,
    promoteWindowToMain = promoteToMain,
    promoteWindow = promoteWindow,
    demoteWindow = demoteWindow,
    floatWindow = floatWindow,
    stopTiling = stopTiling
  }
  for action, hotkey in pairs(config.hotkeys) do
    if handlers[action] then
      bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action])
    end
  end

  if next(bindings) then
    topOffset = config.topOffset or 0
    padding = config.padding or 0
    splitRatios = config.splitRatios or { 0.5, 0.33, 0.67 }
    initialNumberOfStackedWindows = config.initialNumberOfStackedWindows or 1
    excludedApps = {}
    for _, appName in ipairs(config.excludeApps or {}) do
      excludedApps[appName] = true
    end

    screenWatcher = hs.screen.watcher.new(updateTiledSpaces):start()
    applicationWatcher = hs.application.watcher.new(function(_, event, _)
      if event == hs.application.watcher.terminated then
        updateManagedWindowsDebounced()
      end
    end):start()

    windowFilter = hs.window.filter.new():setOverrideFilter({
      allowRoles = { "AXStandardWindow" },
      currentSpace = true,
      fullscreen = false,
      visible = true
    })

    for appName, _ in pairs(excludedApps) do
      windowFilter:rejectApp(appName)
    end

    windowFilter:subscribe(
      { hs.window.filter.windowsChanged, hs.window.filter.windowFocused },
      updateManagedWindowsDebounced
    )
  end

  return module
end

function module.cleanup()
  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}

  if screenWatcher then screenWatcher:stop() end
  screenWatcher = nil

  if applicationWatcher then applicationWatcher:stop() end
  applicationWatcher = nil

  if windowFilter then windowFilter:unsubscribeAll() end
  windowFilter = nil

  if debounceTimer then debounceTimer:stop() end
  debounceTimer = nil

  for spaceID, _ in pairs(tiledSpaces) do restoreAllWindows(spaceID) end
  tiledSpaces = {}
end

return module
