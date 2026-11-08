import AppKit

extension NSScreen {
  static var screenContainingMouse: NSScreen? { screen(containing: NSEvent.mouseLocation) }

  static func screen(containing point: CGPoint) -> NSScreen? {
    return screens.first { NSMouseInRect(point, $0.frame, false) }
  }

  static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
    return screens.first { $0.cgDirectDisplayID == displayID }
  }
}
