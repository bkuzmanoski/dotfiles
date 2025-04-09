local utils = require("utils")

local module = {}
local windowFilter, keyboardTap, mouseTap
local screenFrame, allWindows, activeWindow, activeOperation, initialWindowFrame, initialMousePosition
local topOffset, padding, snapThreshold, moveModifiers, resizeModifiers, rejectApps

local function getWindowUnderMouse(windows)
  local rawMousePosition = hs.mouse.absolutePosition()

  -- Get window of topmost element under mouse
  local elementUnderMouse = hs.axuielement.systemWideElement():elementAtPosition(rawMousePosition)
  if elementUnderMouse then
    local rawWindow = elementUnderMouse:attributeValue("AXWindow")
    if rawWindow and rawWindow:attributeValue("AXSubrole") == "AXStandardWindow" then return rawWindow:asHSWindow() end
  end

  -- If topmost element is not (or not in) an AXStandardWindow, fall back to the frontmost window under the mouse
  local mousePosition = hs.geometry.new(rawMousePosition)
  for _, window in ipairs(windows) do
    if mousePosition:inside(window:frame()) then return window end
  end

  return nil
end

local function snapToEdges(screenBoundary, windows, operation, frame, deltaX, deltaY, threshold)
  if threshold == 0 then return nil, nil end

  local function findClosestEdge(value, edges)
    local minDistance = threshold + 1
    local closestEdge = nil
    local closestEdgeType = nil
    for _, edge in ipairs(edges) do
      local distance = math.abs(value - edge.position)
      if distance < minDistance then
        minDistance = distance
        closestEdge = edge.position
        closestEdgeType = edge.type
      end
    end
    return closestEdge, closestEdgeType
  end

  local horizontalEdges = {}
  local verticalEdges = {}

  -- Add screen edges
  table.insert(verticalEdges, { position = screenBoundary.x, type = "screenLeft" })
  table.insert(verticalEdges, { position = screenBoundary.x + screenBoundary.w, type = "screenRight" })
  table.insert(horizontalEdges, { position = screenBoundary.y, type = "screenTop" })
  table.insert(horizontalEdges, { position = screenBoundary.y + screenBoundary.h, type = "screenBottom" })

  -- Add window edges
  for _, window in ipairs(windows) do
    if window ~= activeWindow then
      local windowFrame = window:frame()
      table.insert(verticalEdges, { position = windowFrame.x, type = "windowLeft" })
      table.insert(verticalEdges, { position = windowFrame.x + windowFrame.w, type = "windowRight" })
      table.insert(horizontalEdges, { position = windowFrame.y, type = "windowTop" })
      table.insert(horizontalEdges, { position = windowFrame.y + windowFrame.h, type = "windowBottom" })
      if padding > 1 then -- 1px offset applied to each edge by default, so padding of 0 is equivalent to 1px
        table.insert(verticalEdges, { position = windowFrame.x - padding, type = "paddedWindowLeft" })
        table.insert(verticalEdges, { position = windowFrame.x + windowFrame.w + padding, type = "paddedWindowRight" })
        table.insert(horizontalEdges, { position = windowFrame.y - padding, type = "paddedWindowTop" })
        table.insert(horizontalEdges, { position = windowFrame.y + windowFrame.h + padding, type = "paddedWindowBottom" })
      end
    end
  end

  if operation == "move" then
    local targetX = frame.x + deltaX
    local targetY = frame.y + deltaY
    local targetRight = frame.x + frame.w + deltaX
    local targetBottom = frame.y + frame.h + deltaY
    local snappedX, snappedXType = findClosestEdge(targetX, verticalEdges)
    local snappedY, snappedYType = findClosestEdge(targetY, horizontalEdges)
    local snappedRight, snappedRightType = findClosestEdge(targetRight, verticalEdges)
    local snappedBottom, snappedBottomType = findClosestEdge(targetBottom, horizontalEdges)

    -- Apply 1px offset if snapping to window edges
    if snappedX and snappedXType == "windowRight" then snappedX = snappedX + 1 end
    if snappedY and snappedYType == "windowBottom" then snappedY = snappedY + 1 end
    if snappedRight and snappedRightType == "windowLeft" then snappedRight = snappedRight - 1 end
    if snappedBottom and snappedBottomType == "windowTop" then snappedBottom = snappedBottom - 1 end

    -- If bottom/right edge snapped, convert to top/left edge position
    if snappedRight then snappedX = snappedRight - frame.w end
    if snappedBottom then snappedY = snappedBottom - frame.h end

    if snappedX or snappedY then
      return snappedX or (frame.x + deltaX), snappedY or (frame.y + deltaY)
    end
  elseif operation == "resize" then
    local targetRight = frame.x + frame.w + deltaX
    local targetBottom = frame.y + frame.h + deltaY
    local snappedRight, snappedRightType = findClosestEdge(targetRight, verticalEdges)
    local snappedBottom, snappedBottomType = findClosestEdge(targetBottom, horizontalEdges)

    if snappedRight or snappedBottom then
      -- Apply 1px offset if snapping to window edges
      if snappedRight and snappedRightType == "windowLeft" then snappedRight = snappedRight - 1 end
      if snappedBottom and snappedBottomType == "windowTop" then snappedBottom = snappedBottom - 1 end

      return
          (snappedRight and (snappedRight - frame.x)) or (frame.w + deltaX),
          (snappedBottom and (snappedBottom - frame.y)) or (frame.h + deltaY)
    end
  end

  return nil, nil
end

local function startOperation(operationType)
  allWindows = windowFilter:getWindows()
  activeWindow = getWindowUnderMouse(allWindows)
  if not activeWindow then return end

  local appName = activeWindow:application():name()
  for _, app in ipairs(rejectApps) do
    if app == appName then return end
  end

  if (operationType == "resize") and not activeWindow:isMaximizable() then return end

  screenFrame = utils.getAdjustedScreenFrame(activeWindow:screen():fullFrame(), topOffset, padding)
  activeOperation = operationType
  initialWindowFrame = activeWindow:frame()
  initialMousePosition = hs.mouse.absolutePosition()
  mouseTap:start()
end

local function stopOperation()
  if mouseTap then mouseTap:stop() end
  screenFrame = nil
  allWindows = nil
  activeWindow = nil
  activeOperation = nil
  initialWindowFrame = nil
  initialMousePosition = nil
end

local function handleFlagsChange(event)
  stopOperation()

  local flags = event:getFlags()
  if moveModifiers and flags:containExactly(moveModifiers) then
    startOperation("move")
  elseif resizeModifiers and flags:containExactly(resizeModifiers) then
    startOperation("resize")
  end
end

local function handleMouseMove()
  if activeOperation and activeWindow and initialWindowFrame and initialMousePosition then
    local currentMousePosition = hs.mouse.absolutePosition()
    local deltaX = currentMousePosition.x - initialMousePosition.x
    local deltaY = currentMousePosition.y - initialMousePosition.y

    local newFrame = initialWindowFrame:copy()
    local newX, newY = snapToEdges(
      screenFrame, allWindows, activeOperation, initialWindowFrame, deltaX, deltaY, snapThreshold)
    if activeOperation == "move" then
      newFrame.x = newX or (newFrame.x + deltaX)
      newFrame.y = newY or (newFrame.y + deltaY)
    elseif activeOperation == "resize" then
      newFrame.w = newX or (newFrame.w + deltaX)
      newFrame.h = newY or (newFrame.h + deltaY)
    end
    activeWindow:setFrame(newFrame, 0)
  end
end

function module.init(config)
  if keyboardTap or mouseTap then module.cleanup() end

  if config and (config.moveModifiers or config.resizeModifiers) then
    topOffset = config.topOffset or 0
    padding = config.padding or 0
    snapThreshold = config.snapThreshold or 0
    moveModifiers = config.moveModifiers
    resizeModifiers = config.resizeModifiers
    rejectApps = config.rejectApps or {}

    windowFilter = hs.window.filter.new()
        :setOverrideFilter({ allowRoles = { "AXStandardWindow" }, currentSpace = true, fullscreen = false, visible = true })
    keyboardTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, handleFlagsChange):start()
    mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, handleMouseMove) -- Don't start yet
  end

  return module
end

function module.cleanup()
  stopOperation()

  if keyboardTap then keyboardTap:stop() end
  keyboardTap = nil

  if mouseTap then mouseTap:stop() end
  mouseTap = nil
end

return module
