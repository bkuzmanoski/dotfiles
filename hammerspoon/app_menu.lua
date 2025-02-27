local module = {}
local clickTap

module.targetArea = {}
module.rightClickModifiers = {}

function module.init()
  if next(module.targetArea) and next(module.rightClickModifiers) then
    clickTap = hs.eventtap.new({ hs.eventtap.event.types.leftMouseDown }, function(event)
      local eventLocation = event:location()
      local clickPoint = hs.geometry(eventLocation.x, eventLocation.y)
      local screen = hs.screen.mainScreen():fullFrame()
      local targetArea = hs.geometry(
        screen.x + module.targetArea.x,
        screen.y + module.targetArea.y,
        screen.x + module.targetArea.x + module.targetArea.w,
        screen.y + module.targetArea.y + module.targetArea.h
      )
      if clickPoint:inside(targetArea) then
        hs.eventtap.event.newMouseEvent(
          hs.eventtap.event.types.rightMouseDown,
          clickPoint,
          module.rightClickModifiers
        ):post()
        hs.eventtap.event.newMouseEvent(
          hs.eventtap.event.types.rightMouseUp,
          clickPoint,
          module.rightClickModifiers
        ):post()
        return true
      end
      return false
    end)
    clickTap:start()
  end
end

function module.cleanup()
  if clickTap then
    clickTap:stop()
    clickTap = nil
  end
end

return module
