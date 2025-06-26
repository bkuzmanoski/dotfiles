local utils = require("utils")

local module = {}
local bindings = {}
local tiledSpaces = {}
local screenWatcher, windowFilter, debounceTimer
local topOffset, padding, splitRatios, initialNumberOfStackedWindows, excludedApps, excludeWindowsLessThanWidth

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

local function getCurrentSpaceAndScreen()
  local screen = hs.screen.mainScreen()
  if not screen then return nil, nil end

  local spacesData = hs.spaces.data_managedDisplaySpaces()
  if not spacesData then return nil, nil end

  local screenUUID = screen:getUUID()
  for _, display in ipairs(spacesData) do
    if display["Display Identifier"] == screenUUID then
      local spaceId = display["Current Space"].ManagedSpaceID
      if not spaceId then return nil, nil end

      return spaceId, screen
    end
  end

  return nil, nil
end

local function getWindowsInCurrentSpace()
  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return {} end

  -- Don't use windowFilter.getWindows() as it becomes out of sync with actual window state when using tabs
  local windows = hs.window.visibleWindows()
  if not windows or #windows == 0 then return {} end

  local screenFrame = screen:fullFrame()
  local windowsToManage = hs.fnutils.ifilter(windows, function(window)
    local windowFrame = window:frame()
    return window:isMaximizable() and
        windowFrame ~= screenFrame and windowFrame.w >= excludeWindowsLessThanWidth and
        window:screen() == screen and #hs.spaces.windowSpaces(window) == 1 and
        window:application() and not excludedApps[window:application():name()]
  end)

  return hs.fnutils.imap(windowsToManage, function(window)
    return { window = window, initialFrame = window:frame() }
  end)
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


local function restoreWindow(tilingState, windowIndex)
  local windowData = tilingState.managedWindows[windowIndex]
  if not windowData or not windowData.window then return end

  local windowId = windowData.window:id()
  if not windowId then return end

  local savedFrame = tilingState.savedWindowFrames[windowId]
  if not savedFrame then return end

  windowData.window:setFrame(savedFrame)
end

local function restoreWindows(spaceId)
  local tilingState = tiledSpaces[spaceId]
  if not tilingState then return end
  for i, _ in ipairs(tilingState.managedWindows) do
    restoreWindow(tilingState, i)
  end
end

local function applyLayout()
  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return end

  local tilingState = tiledSpaces[spaceId]
  if not tilingState or #tilingState.managedWindows == 0 then return end

  local screenFrame = utils.getAdjustedScreenFrame(screen, topOffset, padding)
  local newWindowStates = {}
  if #tilingState.managedWindows == 1 or tilingState.numberOfStackedWindows == 0 then
    table.insert(newWindowStates, { window = tilingState.managedWindows[1].window, frame = screenFrame })
  else
    local mainWindowFrame, stackBoundingRect =
        dividedRect(screenFrame, tilingState.splitRatio, tilingState.mainWindowEdge, padding)
    table.insert(newWindowStates, { window = tilingState.managedWindows[1].window, frame = mainWindowFrame })

    local stackWindows = {}
    local endIndex = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
    for i = 2, endIndex do table.insert(stackWindows, tilingState.managedWindows[i].window) end

    if #stackWindows > 0 then
      local isHorizontal = tilingState.mainWindowEdge == edge.top or tilingState.mainWindowEdge == edge.bottom
      local stackFrames = layoutStackWindows(stackWindows, stackBoundingRect, padding, isHorizontal)
      for _, stackFrame in ipairs(stackFrames) do table.insert(newWindowStates, stackFrame) end
    end
  end

  for _, windowState in ipairs(newWindowStates) do windowState.window:setFrame(windowState.frame) end

  for i = #newWindowStates + 1, #tilingState.managedWindows do
    restoreWindow(tilingState, i)
  end
end

local function updateManagedWindows()
  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return end

  local tilingState = tiledSpaces[spaceId]
  if not tilingState then return end

  local currentWindows = getWindowsInCurrentSpace()
  if #currentWindows == 0 then
    tiledSpaces[spaceId] = nil
    return
  end

  local currentWindowsMap = hs.fnutils.reduce(currentWindows, function(acc, windowData)
    acc[windowData.window:id()] = windowData
    return acc
  end, {})
  local existingWindowIds = hs.fnutils.reduce(tilingState.managedWindows, function(acc, windowData)
    acc[windowData.window:id()] = true
    return acc
  end, {})
  local retainedWindows = hs.fnutils.ifilter(tilingState.managedWindows, function(windowData)
    return currentWindowsMap[windowData.window:id()] ~= nil
  end)
  local newWindows = hs.fnutils.ifilter(currentWindows, function(windowData)
    return not existingWindowIds[windowData.window:id()]
  end)

  tilingState.managedWindows = hs.fnutils.concat(retainedWindows, newWindows)
  tilingState.savedWindowFrames = hs.fnutils.reduce(newWindows, function(acc, windowData)
    acc[windowData.window:id()] = windowData.initialFrame
    return acc
  end, tilingState.savedWindowFrames or {})

  -- Update saved frames for floating windows
  local tiledWindowCount = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
  for i = tiledWindowCount + 1, #tilingState.managedWindows do
    local windowData = tilingState.managedWindows[i]
    if windowData and windowData.window then
      local windowId = windowData.window:id()
      if windowId then
        tilingState.savedWindowFrames[windowId] = windowData.window:frame()
      end
    end
  end

  tiledSpaces[spaceId] = tilingState
  applyLayout()
end

local function updateManagedWindowsDebounced()
  if debounceTimer then debounceTimer:stop() end
  debounceTimer = hs.timer.doAfter(0.2, updateManagedWindows)
end

local function updateTiledSpaces()
  local currentScreenIds = hs.fnutils.reduce(hs.screen.allScreens(), function(acc, screen)
    acc[screen:id()] = true
    return acc
  end, {})

  for spaceId, tilingState in pairs(tiledSpaces) do
    local screenId = tilingState.screen:id()
    if not screenId or not currentScreenIds[screenId] then
      restoreWindows(spaceId)
      tiledSpaces[spaceId] = nil
    end
  end
end

local function tile(mainWindowEdge)
  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return end

  local tilingState = tiledSpaces[spaceId]
  local newTilingState

  if tilingState then
    newTilingState = tilingState
    if tilingState.mainWindowEdge == mainWindowEdge then
      newTilingState.splitRatio = utils.cycleNext(splitRatios, tilingState.splitRatio)
    else
      newTilingState.mainWindowEdge = mainWindowEdge
      -- If swapping main window and stack, keep split ratio; otherwise reset
      if getOppositeEdge(tilingState.mainWindowEdge) ~= mainWindowEdge then
        newTilingState.splitRatio = utils.cycleNext(splitRatios)
      end
    end
  else
    local windowsToManage = getWindowsInCurrentSpace()
    if #windowsToManage == 0 then return end

    local savedFrames = {}
    for _, windowData in ipairs(windowsToManage) do
      savedFrames[windowData.window:id()] = windowData.initialFrame
    end

    newTilingState = {
      screen = screen,
      splitRatio = splitRatios[1],
      mainWindowEdge = mainWindowEdge,
      numberOfStackedWindows = initialNumberOfStackedWindows,
      managedWindows = windowsToManage,
      savedWindowFrames = savedFrames
    }
  end

  tiledSpaces[spaceId] = newTilingState
  applyLayout()
end

local function updateStackSize(amount)
  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return end

  local tilingState = tiledSpaces[spaceId]
  if not tilingState or #tilingState.managedWindows <= 1 then return end

  tilingState.numberOfStackedWindows =
      math.max(0, math.min(#tilingState.managedWindows - 1, tilingState.numberOfStackedWindows + amount))
  tiledSpaces[spaceId] = tilingState
  applyLayout()
end

local function promoteToMain()
  local window = hs.window.focusedWindow()
  if not window then return end

  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return end

  local tilingState = tiledSpaces[spaceId]
  if not tilingState or #tilingState.managedWindows == 0 then return end

  for i, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window:id() == window:id() then
      table.remove(tilingState.managedWindows, i)
      table.insert(tilingState.managedWindows, 1, windowData)
      tiledSpaces[spaceId] = tilingState
      applyLayout()

      return
    end
  end
end

local function promoteWindow()
  local window = hs.window.focusedWindow()
  if not window then return end

  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return end

  local tilingState = tiledSpaces[spaceId]
  if not tilingState or #tilingState.managedWindows <= 1 then return end

  local endIndex = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
  for i, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window:id() == window:id() then
      if i == 1 then return end

      local windowToMove = table.remove(tilingState.managedWindows, i)
      if i > endIndex then
        table.insert(tilingState.managedWindows, endIndex, windowToMove)
      else
        table.insert(tilingState.managedWindows, i - 1, windowToMove)
      end

      tiledSpaces[spaceId] = tilingState
      applyLayout()

      return
    end
  end
end

local function demoteWindow()
  local window = hs.window.focusedWindow()
  if not window then return end

  local spaceId, screen = getCurrentSpaceAndScreen()
  if not spaceId or not screen then return end

  local tilingState = tiledSpaces[spaceId]
  if not tilingState or #tilingState.managedWindows <= 1 then return end

  local stackEnd = math.min(tilingState.numberOfStackedWindows + 1, #tilingState.managedWindows)
  for i, windowData in ipairs(tilingState.managedWindows) do
    if windowData.window:id() == window:id() then
      if i > stackEnd or i == #tilingState.managedWindows then return end

      local windowToMove = table.remove(tilingState.managedWindows, i)
      table.insert(tilingState.managedWindows, i + 1, windowToMove)
      tiledSpaces[spaceId] = tilingState
      applyLayout()

      return
    end
  end
end

local function stopTiling()
  local spaceId = getCurrentSpaceAndScreen()
  if not spaceId then return end

  restoreWindows(spaceId)
  tiledSpaces[spaceId] = nil
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
    excludedApps = hs.fnutils.reduce(config.excludeApps or {}, function(acc, appName)
      acc[appName] = true
      return acc
    end, {})
    excludeWindowsLessThanWidth = config.excludeWindowsLessThanWidth or 0

    windowFilter = hs.window.filter.new()
        :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, currentSpace = true, fullscreen = false, visible = true })
        :subscribe(hs.window.filter.windowOnScreen, updateManagedWindowsDebounced)
        :subscribe(hs.window.filter.windowNotOnScreen, updateManagedWindowsDebounced)
        :subscribe(hs.window.filter.windowMoved, updateManagedWindowsDebounced)
    screenWatcher = hs.screen.watcher.new(updateTiledSpaces):start()
  end

  return module
end

function module.cleanup()
  if debounceTimer then debounceTimer:stop() end
  debounceTimer = nil

  for _, binding in pairs(bindings) do binding:delete() end
  bindings = {}

  if screenWatcher then screenWatcher:stop() end
  screenWatcher = nil

  if windowFilter then windowFilter:unsubscribeAll() end
  windowFilter = nil

  for spaceId, _ in pairs(tiledSpaces) do restoreWindows(spaceId) end
  tiledSpaces = {}
end

return module
