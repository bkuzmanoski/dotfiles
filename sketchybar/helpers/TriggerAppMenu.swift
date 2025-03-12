import Cocoa
import Foundation

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(_ cid: Int, _ ownerCid: Int, _ key: CFString, _ value: CFTypeRef)
  -> Int

func getAbsoluteClickTarget(mouseLocation: CGPoint, relativeX: CGFloat, relativeY: CGFloat)
  -> CGPoint
{
  var displayCount: UInt32 = 0
  guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
    return CGPoint(x: relativeX, y: relativeY)
  }

  var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
  guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
    return CGPoint(x: relativeX, y: relativeY)
  }

  var currentDisplayBounds = CGDisplayBounds(CGMainDisplayID())
  for display in displays {
    let displayBounds = CGDisplayBounds(display)
    if displayBounds.contains(mouseLocation) {
      currentDisplayBounds = displayBounds
      break
    }
  }

  let absoluteX = currentDisplayBounds.origin.x + relativeX
  let absoluteY = currentDisplayBounds.origin.y + relativeY

  return CGPoint(x: absoluteX, y: absoluteY)
}

guard CommandLine.arguments.count == 3,
  let targetX = Double(CommandLine.arguments[1]),
  let targetY = Double(CommandLine.arguments[2])
else {
  print("Usage: \(CommandLine.arguments[0]) x y")
  exit(1)
}

let semaphoreFile = "/tmp/TriggerAppMenu"
let instanceID = UUID().uuidString
let startTime = Date()

defer {
  if let data = try? Data(contentsOf: URL(fileURLWithPath: semaphoreFile)),
    let fileID = String(data: data, encoding: .utf8),
    fileID == instanceID
  {
    try? fileManager.removeItem(atPath: semaphoreFile)
  }
}

let fileManager = FileManager.default
if fileManager.fileExists(atPath: semaphoreFile) {
  if let attrs = try? fileManager.attributesOfItem(atPath: semaphoreFile),
    let modDate = attrs[.modificationDate] as? Date,
    Date().timeIntervalSince(modDate) < 5.0
  {
    exit(0)
  } else {
    try? fileManager.removeItem(atPath: semaphoreFile)
  }
}

fileManager.createFile(atPath: semaphoreFile, contents: Data(instanceID.utf8), attributes: nil)

let cid = CGSMainConnectionID()
let hideKey = "SetsCursorInBackground" as CFString

defer {
  CGDisplayShowCursor(CGMainDisplayID())
  _ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanFalse)
  usleep(50000)
}

_ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanTrue)
CGDisplayHideCursor(CGMainDisplayID())

let eventSource = CGEventSource(stateID: .combinedSessionState)
let mouseLocation = CGEvent(source: nil)?.location ?? CGPoint.zero
let clickTarget = getAbsoluteClickTarget(
  mouseLocation: mouseLocation,
  relativeX: targetX,
  relativeY: targetY
)

let moveToPosition = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: clickTarget,
  mouseButton: .left
)
moveToPosition?.post(tap: .cghidEventTap)

usleep(30000)

let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(46), keyDown: true)
keyDown?.flags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
keyDown?.post(tap: .cghidEventTap)

let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(46), keyDown: false)
keyUp?.flags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
keyUp?.post(tap: .cghidEventTap)

usleep(30000)

let moveBack = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: mouseLocation,
  mouseButton: .left
)
moveBack?.post(tap: .cghidEventTap)

usleep(30000)
