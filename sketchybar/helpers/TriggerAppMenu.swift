import Cocoa
import Foundation

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(_ cid: Int, _ ownerCid: Int, _ key: CFString, _ value: CFTypeRef)
  -> Int

guard CommandLine.arguments.count == 3,
  let x = Double(CommandLine.arguments[1]),
  let y = Double(CommandLine.arguments[2])
else {
  print("Usage: \(CommandLine.arguments[0]) x y")
  exit(1)
}

// Ensure only one instance is running to avoid cursor state issues
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
    // print("Another instance appears to be running. Exiting.")
    exit(0)
  } else {
    try? fileManager.removeItem(atPath: semaphoreFile)
  }
}

fileManager.createFile(atPath: semaphoreFile, contents: Data(instanceID.utf8), attributes: nil)

// Hide cursor to hide visual jump
let cid = CGSMainConnectionID()
let hideKey = "SetsCursorInBackground" as CFString

defer {
  CGDisplayShowCursor(CGMainDisplayID())
  _ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanFalse)
  usleep(50000)
}

_ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanTrue)
CGDisplayHideCursor(CGMainDisplayID())

// Trigger MenuWhere
let eventSource = CGEventSource(stateID: .combinedSessionState)
let startingPosition = CGEvent(source: nil)?.location ?? CGPoint.zero
let clickTarget = CGPoint(x: x, y: y)

let moveToPosition = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: clickTarget,
  mouseButton: .left
)
moveToPosition?.post(tap: .cghidEventTap)

usleep(25000)

let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(46), keyDown: true)
keyDown?.flags = [.maskCommand, .maskControl, .maskAlternate]
keyDown?.post(tap: .cghidEventTap)

let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(46), keyDown: false)
keyUp?.flags = [.maskCommand, .maskControl, .maskAlternate]
keyUp?.post(tap: .cghidEventTap)

usleep(10000)

let moveBack = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: startingPosition,
  mouseButton: .left
)
moveBack?.post(tap: .cghidEventTap)

usleep(25000)
