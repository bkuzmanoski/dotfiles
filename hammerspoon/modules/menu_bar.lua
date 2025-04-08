local utils = require("utils")

local module = {}
local displayWatcher, windowSubscription, uiElementWatcher, updateTimer
local height, horizontalPadding, widgetGap
local menuBars = {}

local appIconSize = 23
local elementGap = 7
local fonts = {
  emphasis = { name = ".AppleSystemUIFontDemi", size = 13 },
  regular = { name = ".AppleSystemUIFont", size = 13 },
  icon = { name = ".AppleSystemUIFontLight", size = 15 }
}
local shadows = {
  appIcon = { blurRadius = 2, color = { red = 0, green = 0, blue = 0, alpha = 0.2 }, offset = { h = -1, w = 0 } },
  text = { blurRadius = 2, color = { red = 0, green = 0, blue = 0, alpha = 0.1 }, offset = { h = -1, w = 0 } }
}
local colors = {
  lightAppearance = {
    default = { background = { red = 246, green = 246, blue = 246, alpha = 0.36 }, icon = { red = 0, green = 0, blue = 0, alpha = 1 }, text = { red = 0, green = 0, blue = 0, alpha = 1 } },
    warning = { background = { red = 246, green = 246, blue = 246, alpha = 0.36 }, icon = { red = 255, green = 59, blue = 48, alpha = 1 }, text = { red = 255, green = 59, blue = 48, alpha = 1 } }
  },
  darkAppearance = {
    default = { background = { red = 74, green = 74, blue = 74, alpha = 0.39 }, icon = { red = 255, green = 255, blue = 255, alpha = 1 }, text = { red = 255, green = 255, blue = 255, alpha = 1 } },
    warning = { background = { red = 74, green = 74, blue = 74, alpha = 0.39 }, icon = { red = 255, green = 69, blue = 58, alpha = 1 }, text = { red = 255, green = 69, blue = 58, alpha = 1 } }
  }
}

local function createAppInfoWidget(widgetId, side, style, systemAppearance)
  local app = utils.getMenuBarOwningApp()
  local bundleId = app:bundleID()
  local mainWindow = app:mainWindow()
  local appIcon = {
    id = widgetId .. ":appIcon:" .. side,
    type = "image",
    image = hs.image.imageFromAppBundle(bundleId),
    frame = {
      x = 0,
      y = (style.height - style.appIconSize) / 2,
      w = style.appIconSize,
      h = style.appIconSize
    },
    withShadow = true,
    shadow = style.shadows.appIcon
  }
  local appName = {
    id = widgetId .. ":appName:" .. side,
    type = "text",
    text = hs.styledtext.new(hs.application.infoForBundleID(bundleId).CFBundleName or app:name(), {
      font = style.fonts.emphasis,
      color = colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }
  local windowTitle = {
    id = widgetId .. ":windowTitle:" .. side,
    type = "text",
    text = hs.styledtext.new(mainWindow and mainWindow:title() or "", {
      font = style.fonts.regular,
      color = style.colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }

  if side == "left" then
    return appIcon, appName, windowTitle
  elseif side == "right" then
    return windowTitle, appName, appIcon
  end
end


local function createNextEventWidget(widgetId, side, style, systemAppearance)
  local eventIcon = {
    id = widgetId .. ":eventIcon:" .. side,
    type = "text",
    text = hs.styledtext.new("􀉉", {
      font = style.fonts.icon,
      color = style.colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }
  local eventLabel = {
    id = widgetId .. ":eventLabel:" .. side,
    type = "text",
    text = hs.styledtext.new("Call Sebastian • in 3m", { -- TODO: Get meeting info
      font = style.fonts.regular,
      color = style.colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }

  if side == "left" then
    return eventIcon, eventLabel
  elseif side == "right" then
    return eventLabel, eventIcon
  end
end

local function createLowBatteryWarningWidget(widgetId, side, style, systemAppearance)
  local batteryIcon = {
    id = widgetId .. ":batteryIcon:" .. side,
    type = "text",
    text = hs.styledtext.new("􀛩", {
      font = style.fonts.icon,
      color = style.colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }
  local batteryPercentage = {
    id = widgetId .. ":batteryPercentage:" .. side,
    type = "text",
    text = hs.styledtext.new("39%", { -- TODO: Get battery percentage
      font = style.fonts.regular,
      color = style.colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }

  if side == "left" then
    return batteryIcon, batteryPercentage
  elseif side == "right" then
    return batteryPercentage, batteryIcon
  end
end

local function createDateTimeWidget(widgetId, side, style, systemAppearance)
  local date = {
    id = widgetId .. ":date:" .. side,
    type = "text",
    text = hs.styledtext.new(tostring(os.date("%a %d %b")):gsub(" 0", " "), {
      font = style.fonts.regular,
      color = style.colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }
  local time = {
    id = widgetId .. ":time:" .. side,
    type = "text",
    text = hs.styledtext.new(tostring(os.date("%I:%M %p")):gsub("^0", ""):gsub("1", " 1"):lower(), {
      font = style.fonts.regular,
      color = style.colors[systemAppearance].default.text
    }),
    frame = {},
    withShadow = true,
    shadow = style.shadows.text
  }

  if side == "left" then
    return date, time
  elseif side == "right" then
    return time, date
  end
end

local widgets = {
  -- In layout order (left to right for left side, right to left for right side)
  { id = "appInfo",           side = "left",  create = createAppInfoWidget },
  { id = "dateTime",          side = "right", create = createDateTimeWidget },
  { id = "lowBatteryWarning", side = "right", create = createLowBatteryWarningWidget },
  { id = "nextEvent",         side = "right", create = createNextEventWidget }
}

local function updateLayout(menuBarToRefresh)
  local menuBarsToRefresh = menuBarToRefresh and { menuBarToRefresh } or menuBars

  for _, menuBar in pairs(menuBarsToRefresh) do
    local screenFrame = menuBar.screen:fullFrame()
    local canvas = menuBar.canvas
    local lastWidgetIdLeft, lastWidgetIdRight
    local leftOffset = screenFrame.x + horizontalPadding
    local rightOffset = screenFrame.x + screenFrame.w - horizontalPadding
    for i, element in pairs(canvas:canvasElements()) do
      local widgetId, _, side = element.id:match("([^:]*):([^:]*):([^:]*)")
      local widgetBounds = element.type == "text" and
          canvas:minimumTextSize(element.text) or { w = element.frame.w, h = element.frame.h }

      if lastWidgetIdLeft and side == "left" then
        if widgetId ~= lastWidgetIdLeft then
          leftOffset = leftOffset + widgetGap
        else
          leftOffset = leftOffset + elementGap
        end
      elseif lastWidgetIdRight and side == "right" then
        if widgetId ~= lastWidgetIdRight then
          rightOffset = rightOffset - widgetGap
        else
          rightOffset = rightOffset - elementGap
        end
      end

      canvas:elementAttribute(i, "frame", {
        x = side == "left" and leftOffset or rightOffset - widgetBounds.w,
        y = math.floor((canvas:frame().h - widgetBounds.h) / 2),
        w = math.ceil(widgetBounds.w),
        h = widgetBounds.h
      })

      if side == "left" then
        lastWidgetIdLeft = widgetId
        leftOffset = leftOffset + widgetBounds.w
      elseif side == "right" then
        lastWidgetIdRight = widgetId
        rightOffset = rightOffset - widgetBounds.w
      end
    end
  end
end

local function getSystemAppearance()
  return hs.host.interfaceStyle() == "Dark" and "darkAppearance" or "lightAppearance"
end

local function createMenuBar(screen)
  local screenFrame = screen:fullFrame()
  local canvas = hs.canvas.new({ x = screenFrame.x, y = screenFrame.y, w = screenFrame.w, h = height })
      :level(hs.canvas.windowLevels.desktopIcon + 1) -- Minimum level that can reliably receive mouse click events
      :behaviorAsLabels({ "canJoinAllSpaces", "transient" })

  local menuBar = { screen = screen, canvas = canvas }
  menuBars[screen:id()] = menuBar

  local systemAppearance = getSystemAppearance()
  local style = {
    height = height,
    appIconSize = appIconSize,
    elementGap = elementGap,
    fonts = fonts,
    colors = colors,
    shadows = shadows
  }
  for _, widget in ipairs(widgets) do
    menuBar.canvas:appendElements(widget.create(widget.id, widget.side, style, systemAppearance))
  end

  updateLayout(menuBar)
  menuBar.canvas:show()
end

local function destroyMenuBar(screenId)
  if menuBars[screenId] then menuBars[screenId].canvas:delete() end
  menuBars[screenId] = nil
end

local function updateMenuBars()
  local screens = hs.screen.allScreens()
  local activeScreenIds = {}

  for _, screen in ipairs(screens) do
    local screenId = screen:id()
    activeScreenIds[screenId] = true
    if not menuBars[screenId] then createMenuBar(screen) end
  end

  for screenId in pairs(menuBars) do
    if not activeScreenIds[screenId] then destroyMenuBar(screenId) end
  end
end

local function refreshWidgets()
  -- TODO: Refresh widgets properly and move this function up above
  for screenId in pairs(menuBars) do destroyMenuBar(screenId) end
  updateMenuBars()

  if updateTimer then updateTimer:stop() end
  updateTimer = hs.timer.doAfter(60 - (os.time() % 60), refreshWidgets)
end

function module.init(config)
  if displayWatcher or updateTimer or next(menuBars) then module.cleanup() end

  height = config.height or 32
  horizontalPadding = config.horizontalPadding or 8
  widgetGap = config.widgetGap or 16

  displayWatcher = hs.screen.watcher.new(updateMenuBars):start()
  windowSubscription = hs.window.filter.new(config.allowApps)
      :subscribe(hs.window.filter.windowFocused, refreshWidgets)
      :subscribe(hs.window.filter.windowUnfocused, refreshWidgets)
  updateTimer = hs.timer.doAfter(60 - (os.time() % 60), refreshWidgets)

  updateMenuBars()

  return module
end

function module.cleanup()
  if displayWatcher then displayWatcher:stop() end
  displayWatcher = nil

  if windowSubscription then windowSubscription:unsubscribeAll() end
  windowSubscription = nil

  if updateTimer then updateTimer:stop() end
  updateTimer = nil

  for screenId in pairs(menuBars) do destroyMenuBar(screenId) end
end

return module
