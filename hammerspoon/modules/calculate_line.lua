local utils = require("utils")
local module = {}
local binding, windowSubscription

local function calculate()
  local focusedElement = hs.axuielement.systemWideElement():attributeValue("AXFocusedUIElement")
  if not focusedElement then
    utils.playAlert()
    return
  end

  local fullText = focusedElement:attributeValue("AXValue")
  local selectedRange = focusedElement:attributeValue("AXSelectedTextRange")
  if not fullText or not selectedRange then
    utils.playAlert()
    return
  end

  -- Split the text into lines
  local lines = {}
  local position = 1
  while true do
    local lineEnd = fullText:find("\n", position)
    if not lineEnd then
      -- Last line with no newline
      table.insert(lines, fullText:sub(position))
      break
    end
    table.insert(lines, fullText:sub(position, lineEnd - 1))
    position = lineEnd + 1
  end

  -- Find which line contains the cursor
  local cursorPosition = selectedRange.location + 1
  local lineNumber
  local cursorOffset = cursorPosition

  for i, line in ipairs(lines) do
    local lineLength = #line + 1
    if cursorOffset <= lineLength then
      lineNumber = i
      break
    end
    cursorOffset = cursorOffset - lineLength
  end

  if not lineNumber then
    utils.playAlert()
    return
  end

  -- Get the line content and trim for calculation
  local lineText = lines[lineNumber]
  local trimmedLineText = lineText:gsub("^%s*(.*)%s*$", "%1")

  -- Skip if the line is empty (only whitespace)
  if trimmedLineText == "" then
    utils.playAlert()
    return
  end

  -- Run the calculation
  local task = hs.task.new("/bin/zsh", function(exitCode, stdOut)
    if exitCode ~= 0 then
      utils.playAlert()
      return
    end

    -- Remove newlines and trailing whitespace
    stdOut = stdOut:gsub("[\r\n]+", " "):gsub("%s+$", "")

    -- Add result to the end of the line
    local resultText = " [" .. stdOut .. "]"
    lines[lineNumber] = lineText:gsub("%s*$", "") .. resultText

    -- Rebuild the text
    local newText = table.concat(lines, "\n")

    -- Calculate cursor position at the end of the result
    local newCursorPosition = 0
    for i = 1, lineNumber - 1 do
      newCursorPosition = newCursorPosition + #lines[i] + 1
    end
    newCursorPosition = newCursorPosition + #lines[lineNumber]

    -- Update the text field with new cursor position
    focusedElement
        :setAttributeValue("AXValue", newText)
        :setAttributeValue("AXSelectedTextRange", {
          location = newCursorPosition,
          length = 0
        })
  end, { "-c", "source ~/.zsh/.zshenv && source ~/.zsh/utils/wa.zsh && wa " .. string.format("%q", trimmedLineText) })
  task:start()
end

function module.init(config)
  if binding or windowSubscription then module.cleanup() end

  if config.allowApps and #config.allowApps > 0 and config.modifiers and config.key then
    binding = hs.hotkey.bind(config.modifiers, config.key, calculate):disable()
    windowSubscription = hs.window.filter.new(config.allowApps)
        :subscribe(hs.window.filter.windowFocused, function() binding:enable() end)
        :subscribe(hs.window.filter.windowUnfocused, function() binding:disable() end)
  end

  return module
end

function module.cleanup()
  if binding then binding:delete() end
  binding = nil

  if windowSubscription then windowSubscription:unsubscribeAll() end
  windowSubscription = nil
end

return module
