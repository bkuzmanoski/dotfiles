local utils = require("utils")

local module = {}
local keyboardTap, mouseTap
local screenFrame, allWindows, activeWindow, activeOperation, initialWindowFrame, initialMousePosition
local topOffset, padding, snapThreshold, moveModifiers, resizeModifiers, excludedApps

local operationType = { move = "move", resize = "resize" }
local edgeType = {
  windowLeft = "windowLeft",
  windowRight = "windowRight",
  windowTop = "windowTop",
  windowBottom = "windowBottom",
  paddedWindowLeft = "paddedWindowLeft",
  paddedWindowRight = "paddedWindowRight",
  paddedWindowTop = "paddedWindowTop",
  paddedWindowBottom = "paddedWindowBottom",
  screenLeft = "screenLeft",
  screenRight = "screenRight",
  screenTop = "screenTop",
  screenBottom = "screenBottom",
}
local validSubroles = {
  ["AXStandardWindow"] = true,
  ["AXDialog"] = true,
  ["AXSystemDialog"] = true,
  ["AXFloatingWindow"] = true,
  ["AXSystemFloatingWindow"] = true
}

local function getWindowUnderMouse(windows)
  local rawMousePosition = hs.mouse.absolutePosition()

  -- Get window of topmost element under mouse (more reliable than frontmost hit-testing with unfocused windows)
  local elementUnderMouse = hs.axuielement.systemWideElement():elementAtPosition(rawMousePosition)
  if elementUnderMouse then
    -- Element _should_ have an "AXWindow" attribute that points to the window it is in, but
    -- some do not and you have to walk up the parent chain looking for the window element
    local currentElement = elementUnderMouse
    while currentElement do
      local rawWindow = currentElement:attributeValue("AXWindow")
      if rawWindow then
        local subrole = rawWindow:attributeValue("AXSubrole")
        if subrole and validSubroles[subrole] then
          return rawWindow:asHSWindow()
        end
      end

      -- Move to parent element
      currentElement = currentElement:attributeValue("AXParent")
    end
  end

  -- Fall back to the frontmost window under the mouse
  local mousePosition = hs.geometry.new(rawMousePosition)
  for _, window in ipairs(windows) do
    if mousePosition:inside(window:frame()) then return window end
  end

  return nil
end

local function snapToEdges(screenBoundary, windows, operation, frame, deltaX, deltaY, threshold)
  if threshold == 0 then return nil, nil end

  local function findClosestEdge(value, edges)
    local closestEdge = hs.fnutils.reduce(edges, function(acc, edge)
      local distance = math.abs(value - edge.position)
      if distance < acc.minDistance then
        return { minDistance = distance, position = edge.position, type = edge.type }
      end
      return acc
    end, { minDistance = threshold + 1, position = nil, type = nil })

    return closestEdge.position, closestEdge.type
  end

  local horizontalEdges = {}
  local verticalEdges = {}

  -- Add screen edges
  table.insert(verticalEdges, { position = screenBoundary.x, type = edgeType.screenLeft })
  table.insert(verticalEdges, { position = screenBoundary.x + screenBoundary.w, type = edgeType.screenRight })
  table.insert(horizontalEdges, { position = screenBoundary.y, type = edgeType.screenTop })
  table.insert(horizontalEdges, { position = screenBoundary.y + screenBoundary.h, type = edgeType.screenBottom })

  -- Add window edges
  for _, window in ipairs(windows) do
    if window ~= activeWindow then
      local windowFrame = window:frame()
      table.insert(verticalEdges, { position = windowFrame.x, type = edgeType.windowLeft })
      table.insert(verticalEdges, { position = windowFrame.x + windowFrame.w, type = edgeType.windowRight })
      table.insert(horizontalEdges, { position = windowFrame.y, type = edgeType.windowTop })
      table.insert(horizontalEdges, { position = windowFrame.y + windowFrame.h, type = edgeType.windowBottom })
      if padding > 1 then -- 1px offset applied to each edge by default, so padding of 0 is equivalent to 1px
        table.insert(verticalEdges, { position = windowFrame.x - padding, type = edgeType.paddedWindowLeft })
        table.insert(verticalEdges,
          { position = windowFrame.x + windowFrame.w + padding, type = edgeType.paddedWindowRight })
        table.insert(horizontalEdges, { position = windowFrame.y - padding, type = edgeType.paddedWindowTop })
        table.insert(horizontalEdges,
          { position = windowFrame.y + windowFrame.h + padding, type = edgeType.paddedWindowBottom })
      end
    end
  end

  if operation == operationType.move then
    local targetX = frame.x + deltaX
    local targetY = frame.y + deltaY
    local targetRight = frame.x + frame.w + deltaX
    local targetBottom = frame.y + frame.h + deltaY
    local snappedX, snappedXType = findClosestEdge(targetX, verticalEdges)
    local snappedY, snappedYType = findClosestEdge(targetY, horizontalEdges)
    local snappedRight, snappedRightType = findClosestEdge(targetRight, verticalEdges)
    local snappedBottom, snappedBottomType = findClosestEdge(targetBottom, horizontalEdges)

    -- Apply 1px offset if snapping to window edges
    if snappedX and snappedXType == edgeType.windowRight then snappedX = snappedX + 1 end
    if snappedY and snappedYType == edgeType.windowBottom then snappedY = snappedY + 1 end
    if snappedRight and snappedRightType == edgeType.windowLeft then snappedRight = snappedRight - 1 end
    if snappedBottom and snappedBottomType == edgeType.windowTop then snappedBottom = snappedBottom - 1 end

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
      if snappedRight and snappedRightType == edgeType.windowLeft then snappedRight = snappedRight - 1 end
      if snappedBottom and snappedBottomType == edgeType.windowTop then snappedBottom = snappedBottom - 1 end

      return
          (snappedRight and (snappedRight - frame.x)) or (frame.w + deltaX),
          (snappedBottom and (snappedBottom - frame.y)) or (frame.h + deltaY)
    end
  end

  return nil, nil
end

local function startOperation(operation)
  allWindows = hs.window.orderedWindows()
  activeWindow = getWindowUnderMouse(allWindows)
  if not activeWindow or
      excludedApps[activeWindow:application():name()] or
      (operation == operationType.resize and not activeWindow:isMaximizable()) then
    return
  end

  screenFrame = utils.getAdjustedScreenFrame(activeWindow:screen(), topOffset, padding)
  activeOperation = operation
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
    startOperation(operationType.move)
  elseif resizeModifiers and flags:containExactly(resizeModifiers) then
    startOperation(operationType.resize)
  end
end

local function handleMouseMove()
  if activeOperation and activeWindow and initialWindowFrame and initialMousePosition then
    local currentMousePosition = hs.mouse.absolutePosition()
    local deltaX = currentMousePosition.x - initialMousePosition.x
    local deltaY = currentMousePosition.y - initialMousePosition.y

    local newFrame = initialWindowFrame:copy()
    local newX, newY =
        snapToEdges(screenFrame, allWindows, activeOperation, initialWindowFrame, deltaX, deltaY, snapThreshold)
    if activeOperation == operationType.move then
      newFrame.x = newX or (newFrame.x + deltaX)
      newFrame.y = newY or (newFrame.y + deltaY)
    elseif activeOperation == operationType.resize then
      newFrame.w = newX or (newFrame.w + deltaX)
      newFrame.h = newY or (newFrame.h + deltaY)
    end

    activeWindow:setFrame(newFrame, 0)
  end
end

function module.init(config)
  if keyboardTap or mouseTap then module.cleanup() end

  if not config or not (config.moveModifiers or config.resizeModifiers) then return module end

  topOffset = config.topOffset or 0
  padding = config.padding or 0
  snapThreshold = config.snapThreshold or 0
  moveModifiers = config.moveModifiers
  resizeModifiers = config.resizeModifiers
  excludedApps = hs.fnutils.reduce(config.excludeApps or {}, function(acc, appName)
    acc[appName] = true
    return acc
  end, {})

  keyboardTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, handleFlagsChange):start()
  mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, handleMouseMove) -- Don't start yet

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
