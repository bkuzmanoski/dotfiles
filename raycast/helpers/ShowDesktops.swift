import Cocoa
import CoreGraphics

let screenHeight = NSScreen.main?.frame.height ?? 956
let mouseLocation = NSEvent.mouseLocation
let originalX = mouseLocation.x
let originalY = mouseLocation.y

let eventSource = CGEventSource(stateID: .combinedSessionState)
let moveToCorner = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: CGPoint(x: 10, y: 10),
  mouseButton: .left
)
moveToCorner?.post(tap: .cghidEventTap)

let workspace = NSWorkspace.shared
if let appURL = NSWorkspace.shared.urlForApplication(
  withBundleIdentifier: "com.apple.exposelauncher")
{
  let config = NSWorkspace.OpenConfiguration()
  workspace.openApplication(at: appURL, configuration: config) { (app, error) in
    if let error = error {
      print("Error: \(error)")
    }
  }
}

usleep(100000)

// TODO: Use warp to avoid triggering the close signs on desktops

let adjustedY = screenHeight - originalY
let moveBack = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: CGPoint(x: originalX, y: adjustedY),
  mouseButton: .left)
moveBack?.post(tap: .cghidEventTap)
