local utils = require("utils")
local module = {}
local bindings = {}
local windowSubscription

module.allowApps = {}
module.hotkeys = {}

local function moveLines(direction)
  if direction ~= "up" and direction ~= "down" then
    return
  end

  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focusedElement then
    utils.playAlert()
    return
  end

  local fullText = focusedElement:attributeValue("AXValue")
  if not fullText then
    return
  end

  local lines = {}
  local position

  -- Split text into lines, preserving empty lines
  position = 1
  while true do
    local lineEndPosition = fullText:find("\n", position)
    if not lineEndPosition then
      -- Last line
      local line = fullText:sub(position)
      table.insert(lines, line)
      break
    end

    local line = fullText:sub(position, lineEndPosition - 1)
    table.insert(lines, line)
    position = lineEndPosition + 1
  end

  -- Find the line numbers and relative cursor position or selected range
  local startLineNumber, endLineNumber
  local startOffset = 0
  local selectedRange = focusedElement:attributeValue("AXSelectedTextRange")
  if selectedRange and selectedRange.length > 0 then
    -- Handle selection case
    local startPosition = selectedRange.location + 1
    local endPosition = startPosition + selectedRange.length - 1

    -- Find start offset and start and end line numbers
    position = 0
    for i, line in ipairs(lines) do
      local lineLength = #line + 1
      if not startLineNumber and position + lineLength >= startPosition then
        startLineNumber = i
        startOffset = startPosition - position
      end
      if not endLineNumber and position + lineLength >= endPosition then
        endLineNumber = i
        break
      end
      position = position + lineLength
    end
  else
    -- Handle cursor-only case
    local cursorPosition = (selectedRange and selectedRange.location + 1) or 1
    position = 0
    for i, line in ipairs(lines) do
      local lineLength = #line + 1
      if position + lineLength >= cursorPosition then
        startLineNumber = i
        endLineNumber = i
        startOffset = cursorPosition - position
        break
      end
      position = position + lineLength
    end
  end

  if not startLineNumber or not endLineNumber then
    return
  end

  -- Calculate target line based on direction
  local targetLine = direction == "up" and (startLineNumber - 1) or (endLineNumber + 1)
  if targetLine < 1 or targetLine > #lines then
    return
  end

  -- Move the lines
  local movedLines = {}
  if direction == "up" and startLineNumber > 1 then
    for i = startLineNumber, endLineNumber do
      table.insert(movedLines, lines[i])
    end

    for i = endLineNumber, startLineNumber, -1 do
      table.remove(lines, i)
    end

    for i, line in ipairs(movedLines) do
      table.insert(lines, startLineNumber - 1 + i - 1, line)
    end
  elseif direction == "down" and endLineNumber < #lines then
    for i = startLineNumber, endLineNumber do
      table.insert(movedLines, lines[i])
    end

    for i = endLineNumber, startLineNumber, -1 do
      table.remove(lines, i)
    end

    for i, line in ipairs(movedLines) do
      table.insert(lines, startLineNumber + 1 + i - 1, line)
    end
  end

  -- Calculate new selection range
  local updatedStartOffset = 0
  local targetStartLine = direction == "up" and startLineNumber - 1 or startLineNumber + 1
  for i = 1, targetStartLine - 1 do
    updatedStartOffset = updatedStartOffset + #lines[i] + 1
  end

  updatedStartOffset = updatedStartOffset + startOffset - 1

  local updatedEndOffset
  if selectedRange.length > 0 then
    -- Maintain selection
    local selectionLength = selectedRange.length
    updatedEndOffset = updatedStartOffset + selectionLength
  else
    -- Maintain cursor position within line
    updatedEndOffset = updatedStartOffset
  end

  -- Join lines, adding newlines except for last line if original didn't have one
  local reorderedFullText = table.concat(lines, "\n")

  -- Update the text field
  focusedElement
      :setAttributeValue("AXValue", reorderedFullText)
      :setAttributeValue("AXSelectedTextRange", {
        location = updatedStartOffset,
        length = updatedEndOffset - updatedStartOffset
      })
end

local function enableBindings()
  for _, binding in pairs(bindings) do
    binding:enable()
  end
end

local function disableBindings()
  for _, binding in pairs(bindings) do
    binding:disable()
  end
end

function module.init()
  if module.allowApps and #module.allowApps > 0 and next(module.hotkeys) then
    windowSubscription = hs.window.filter.new(module.allowApps)
        :subscribe(hs.window.filter.windowFocused, enableBindings)
        :subscribe(hs.window.filter.windowUnfocused, disableBindings)

    local handlers = {
      moveLinesUp = function() moveLines("up") end,
      moveLinesDown = function() moveLines("down") end
    }
    for action, hotkey in pairs(module.hotkeys) do
      if handlers[action] then
        bindings[action] = hs.hotkey.bind(hotkey.modifiers, hotkey.key, handlers[action], nil, handlers[action])
        bindings[action]:disable()
      end
    end
  end
end

function module.cleanup()
  if windowSubscription then
    windowSubscription:unsubscribeAll()
    windowSubscription = nil
  end
  for _, binding in pairs(bindings) do
    binding:delete()
  end
  bindings = {}
end

return module
