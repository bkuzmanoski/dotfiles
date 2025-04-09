local module = {}
local modifiers
local eventTap

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

local function getAppMenu(app, menuItems, isSubmenu)
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
          app:activate()
          app:selectMenuItem(item.AXTitle)
        end
      }

      if item.AXChildren and #item.AXChildren > 0 then
        local submenuItems = item.AXChildren[1]
        if submenuItems then
          menuItem.menu = getAppMenu(app, submenuItems, true)
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

function module.init(config)
  if eventTap then module.cleanup() end

  if config and config.modifiers and config.triggerEvent then
    modifiers = config.modifiers
    eventTap = hs.eventtap.new({ config.triggerEvent }, handleTriggerEvent):start()
  end

  return module
end

function module.cleanup()
  if eventTap then eventTap:stop() end
  eventTap = nil
end

return module
