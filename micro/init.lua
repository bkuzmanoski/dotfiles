---@diagnostic disable: lowercase-global
---@diagnostic disable: undefined-global

local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")
local strings = import("strings")
local fmt = import("fmt")

local lastSystemAppearance = ""

function init()
  shell.JobStart("${HOME}/.dotfiles/utils/run_command.sh WatchSystemAppearance", onSystemAppearanceChange, nil, nil)

  config.MakeCommand("DeleteToStartOfLine", deleteToStartOfLine, config.NoComplete)
  config.MakeCommand("DeleteToEndOfLine", deleteToEndOfLine, config.NoComplete)
  config.MakeCommand("ToggleList", toggleList, config.NoComplete)
  config.MakeCommand("OpenLinks", openLinks, config.NoComplete)
end

function onSystemAppearanceChange(appearance, _)
  local systemAppearance = strings.TrimSpace(appearance)

  if systemAppearance == "" or systemAppearance == lastSystemAppearance then
    return
  end

  lastSystemAppearance = systemAppearance

  if systemAppearance == "Dark" then
    micro.CurPane():HandleCommand("set colorscheme dark")
  else
    micro.CurPane():HandleCommand("set colorscheme light")
  end
end

function deleteToStartOfLine(bp)
  if bp.Cursor.X == 0 then
    bp:Backspace()
  else
    bp:SelectToStartOfLine()
    bp:Delete()
  end
end

function deleteToEndOfLine(bp)
  bp:SelectToEndOfLine()
  bp:Delete()
end

function toggleList(bp)
  local currentLine = bp.Cursor.Y
  local lineText = bp.Buf:Line(currentLine)
  local indentation = #lineText:match("^(%s*)")
  local remainder = lineText:sub(indentation + 1)

  if remainder:match("^%- ") then
    local textStart = buffer.Loc(indentation, currentLine)
    local textEnd = buffer.Loc(indentation + 2, currentLine)

    bp.Buf:Remove(textStart, textEnd)
  else
    local textStart = buffer.Loc(indentation, currentLine)
    bp.Buf:Insert(textStart, "- ")
  end
end

function openLinks(bp)
  if not bp.Cursor:HasSelection() then
    return
  end

  local selection = fmt.Sprintf("%s", bp.Cursor:GetSelection())
  local tempFile = "/tmp/micro_url_selection_" .. os.time()
  local fileDescriptor = io.open(tempFile, "w")

  if fileDescriptor == nil then
    return
  end

  fileDescriptor:write(selection)
  fileDescriptor:close()

  shell.JobStart(
    string.format("cat %s | ${HOME}/.dotfiles/utils/run_command.sh ExtractURLs | xargs -L1 open", tempFile),
    nil,
    nil,
    function()
      os.remove(tempFile)
    end
  )
end
