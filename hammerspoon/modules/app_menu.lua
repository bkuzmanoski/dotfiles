local module = {}
local modifiers, eventTap

local function getMenuBarOwningApp()
  local ok, pid = hs.osascript.applescript([[
    tell application "System Events"
      set frontApp to first application process whose frontmost is true
      return unix id of frontApp
    end tell
  ]])

  if ok then return hs.application.applicationForPID(pid) end
  return nil
end

local function getAppMenu(application, menuItems, isSubmenu)
  if not menuItems then return nil end

  local formattedMenuItems = {}
  for i, item in ipairs(menuItems) do
    if item.AXTitle == "" then
      table.insert(formattedMenuItems, { title = "-" })
    else
      local menuItem = {
        title = (i == 1 and not isSubmenu) and
            hs.styledtext.new(item.AXTitle, { font = hs.styledtext.defaultFonts.boldSystem }) or
            hs.styledtext.new(item.AXTitle, { font = hs.styledtext.defaultFonts.menu }),
        disabled = not item.AXEnabled,
        checked = (item.AXMenuItemMarkChar == "✓"),
        fn = function()
          application:activate()
          application:selectMenuItem(item.AXTitle)
        end
      }

      if item.AXChildren and #item.AXChildren > 0 then
        local submenuItems = item.AXChildren[1]
        if submenuItems then
          menuItem.menu = getAppMenu(application, submenuItems, true)
        end
      end

      table.insert(formattedMenuItems, menuItem)
    end
  end

  return #formattedMenuItems > 0 and formattedMenuItems or nil
end

local function showAppMenu(position)
  local menuBarOwningApp = getMenuBarOwningApp()
  if not menuBarOwningApp then return end

  local appMenu = getAppMenu(menuBarOwningApp, menuBarOwningApp:getMenuItems())
  if not appMenu then return end

  local menu = hs.menubar.new(false)
  if not menu then return end

  hs.timer.doAfter(0.1, function() menuBarOwningApp:activate() end)
  menu:setMenu(appMenu)
  menu:popupMenu(position)
  menu:delete()
end

local function handleTriggerEvent(event)
  if event:getFlags():containExactly(modifiers) then
    showAppMenu(hs.mouse.absolutePosition())
    return true
  end
  return false
end

local function handleUrlEvent(_, parameters)
  if not parameters.x or not parameters.y then return end

  local x = tonumber(parameters.x)
  local y = tonumber(parameters.y)
  if not x or not y then return end

  local screen = hs.mouse.getCurrentScreen()
  if not screen then return end

  local frame = screen:fullFrame()
  local position = { x = frame.x + x, y = frame.y + y }
  showAppMenu(position)
end

function module.init(config)
  if eventTap then module.cleanup() end

  if config then
    if config.modifiers and config.triggerEvent then
      modifiers = config.modifiers
      eventTap = hs.eventtap.new({ config.triggerEvent }, handleTriggerEvent):start()
    end

    if config.enableUrlEvents then
      hs.urlevent.bind("showAppMenu", handleUrlEvent)
    end
  end

  return module
end

function module.cleanup()
  if eventTap then eventTap:stop() end
  eventTap = nil

  hs.urlevent.bind("showAppMenu", nil)
end

return module
