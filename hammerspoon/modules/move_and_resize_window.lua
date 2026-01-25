local module = {}

local utils = require("utils")
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
  screenBottom = "screenBottom"
}
local validSubroles = {
  ["AXStandardWindow"] = true,
  ["AXDialog"] = true,
  ["AXSystemDialog"] = true,
  ["AXFloatingWindow"] = true,
  ["AXSystemFloatingWindow"] = true
}

local keyboardTap, mouseTap
local topOffset, padding, snapThreshold, moveModifiers, resizeModifiers, excludedApps
local activeOperation, activeWindow, initialWindowFrame, initialMousePosition, screen, allWindows

local function snapToEdges(windows, operation, frame, deltaX, deltaY, threshold)
  if threshold == 0 then
    return nil, nil
  end

  local function findClosestEdge(value, edges)
    local closestEdge = hs.fnutils.reduce(
      edges,
      function(accumulator, edge)
        local distance = math.abs(value - edge.position)

        if distance < accumulator.minDistance then
          return { minDistance = distance, position = edge.position, type = edge.type }
        end

        return accumulator
      end,
      { minDistance = threshold + 1, position = nil, type = nil }
    )

    return closestEdge.position, closestEdge.type
  end

  local horizontalEdges = {}
  local verticalEdges = {}

  local screenFrame = screen:frame()

  table.insert(verticalEdges, { position = screenFrame.x, type = edgeType.screenLeft })
  table.insert(verticalEdges, { position = screenFrame.x + screenFrame.w, type = edgeType.screenRight })
  table.insert(horizontalEdges, { position = screenFrame.y, type = edgeType.screenTop })
  table.insert(horizontalEdges, { position = screenFrame.y + screenFrame.h, type = edgeType.screenBottom })

  if topOffset > 0 or padding > 0 then
    local adjustedScreenFrame = utils.getAdjustedScreenFrame(screen, topOffset, padding)

    table.insert(verticalEdges, { position = adjustedScreenFrame.x, type = edgeType.screenLeft })
    table.insert(verticalEdges, { position = adjustedScreenFrame.x + adjustedScreenFrame.w, type = edgeType.screenRight })
    table.insert(horizontalEdges, { position = adjustedScreenFrame.y, type = edgeType.screenTop })
    table.insert(
      horizontalEdges,
      { position = adjustedScreenFrame.y + adjustedScreenFrame.h, type = edgeType.screenBottom }
    )
  end

  for _, window in ipairs(windows) do
    if window ~= activeWindow then
      local windowFrame = window:frame()

      table.insert(verticalEdges, { position = windowFrame.x, type = edgeType.windowLeft })
      table.insert(verticalEdges, { position = windowFrame.x + windowFrame.w, type = edgeType.windowRight })
      table.insert(horizontalEdges, { position = windowFrame.y, type = edgeType.windowTop })
      table.insert(horizontalEdges, { position = windowFrame.y + windowFrame.h, type = edgeType.windowBottom })
      if padding > 1 then
        table.insert(verticalEdges, { position = windowFrame.x - padding, type = edgeType.paddedWindowLeft })
        table.insert(
          verticalEdges,
          { position = windowFrame.x + windowFrame.w + padding, type = edgeType.paddedWindowRight }
        )
        table.insert(horizontalEdges, { position = windowFrame.y - padding, type = edgeType.paddedWindowTop })
        table.insert(
          horizontalEdges,
          { position = windowFrame.y + windowFrame.h + padding, type = edgeType.paddedWindowBottom }
        )
      end
    end
  end

  if operation == operationType.move then
    local targetStartX = frame.x + deltaX
    local targetEndX = frame.x + frame.w + deltaX
    local targetStartY = frame.y + deltaY
    local targetEndY = frame.y + frame.h + deltaY
    local snappedStartX, snappedStartXType = findClosestEdge(targetStartX, verticalEdges)
    local snappedEndX, snappedEndXType = findClosestEdge(targetEndX, verticalEdges)
    local snappedStartY, snappedStartYType = findClosestEdge(targetStartY, horizontalEdges)
    local snappedEndY, snappedEndYType = findClosestEdge(targetEndY, horizontalEdges)

    if snappedStartX and snappedStartXType == edgeType.windowRight then
      snappedStartX = snappedStartX + 1
    end

    if snappedEndX and snappedEndXType == edgeType.windowLeft then
      snappedEndX = snappedEndX - 1
    end

    if snappedStartY and snappedStartYType == edgeType.windowBottom then
      snappedStartY = snappedStartY + 1
    end

    if snappedEndY and snappedEndYType == edgeType.windowTop then
      snappedEndY = snappedEndY - 1
    end

    if snappedEndX then
      snappedStartX = snappedEndX - frame.w
    end

    if snappedEndY then
      snappedStartY = snappedEndY - frame.h
    end

    if snappedStartX or snappedStartY then
      return snappedStartX or (frame.x + deltaX), snappedStartY or (frame.y + deltaY)
    end
  elseif operation == "resize" then
    local targetEndX = frame.x + frame.w + deltaX
    local targetEndY = frame.y + frame.h + deltaY
    local snappedEndX, snappedEndXType = findClosestEdge(targetEndX, verticalEdges)
    local snappedEndY, snappedEndYType = findClosestEdge(targetEndY, horizontalEdges)

    if snappedEndX or snappedEndY then
      if snappedEndX and snappedEndXType == edgeType.windowLeft then
        snappedEndX = snappedEndX - 1
      end

      if snappedEndY and snappedEndYType == edgeType.windowTop then
        snappedEndY = snappedEndY - 1
      end

      return
          (snappedEndX and (snappedEndX - frame.x)) or (frame.w + deltaX),
          (snappedEndY and (snappedEndY - frame.y)) or (frame.h + deltaY)
    end
  end

  return nil, nil
end

local function startOperation(operation)
  allWindows = hs.window.orderedWindows()
  activeWindow = utils.getWindowUnderMouse(allWindows, validSubroles)

  if
      not activeWindow or
      excludedApps[activeWindow:application():name()] or
      (operation == operationType.resize and not activeWindow:isMaximizable())
  then
    return
  end

  activeOperation = operation
  initialWindowFrame = activeWindow:frame()
  initialMousePosition = hs.mouse.absolutePosition()
  screen = activeWindow:screen()
  mouseTap:start()
end

local function stopOperation()
  if mouseTap then
    mouseTap:stop()
  end

  activeOperation = nil
  activeWindow = nil
  initialWindowFrame = nil
  initialMousePosition = nil
  screen = nil
  allWindows = nil
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
    local newX, newY = snapToEdges(allWindows, activeOperation, initialWindowFrame, deltaX, deltaY, snapThreshold)

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
  if keyboardTap or mouseTap then
    module.cleanup()
  end

  if not config or not (config.moveModifiers or config.resizeModifiers) then
    return module
  end

  topOffset = config.topOffset or 0
  padding = config.padding or 0
  snapThreshold = config.snapThreshold or 0
  moveModifiers = config.moveModifiers
  resizeModifiers = config.resizeModifiers
  excludedApps = {}

  for _, appName in ipairs(config.excludeApps or {}) do
    excludedApps[appName] = true
  end

  keyboardTap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, handleFlagsChange):start()
  mouseTap = hs.eventtap.new({ hs.eventtap.event.types.mouseMoved }, handleMouseMove)

  return module
end

function module.cleanup()
  stopOperation()

  if keyboardTap then
    keyboardTap:stop()
  end

  keyboardTap = nil

  if mouseTap then
    mouseTap:stop()
  end

  mouseTap = nil
end

return module
