#!/usr/bin/swift

import Cocoa
import Foundation

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(_ cid: Int, _ ownerCid: Int, _ key: CFString, _ value: CFTypeRef) -> Int

// Restore cursor visibility and behavior on exit
defer {
  CGDisplayShowCursor(CGMainDisplayID())
  CGAssociateMouseAndMouseCursorPosition(1)
  _ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanFalse)
  try? FileManager.default.removeItem(atPath: lockPath)
}

// Get the target click position to position the menu
guard CommandLine.arguments.count == 3,
  let x = Double(CommandLine.arguments[1]),
  let y = Double(CommandLine.arguments[2])
else {
  print("Usage: \(CommandLine.arguments[0]) x y")
  exit(1)
}

// Check for/create a lock file to prevent recursion
let lockPath = "/tmp/TriggerAppMenu.lock"
if FileManager.default.fileExists(atPath: lockPath) {
  let lockFileAge = Date().timeIntervalSince(
    (try? FileManager.default.attributesOfItem(atPath: lockPath)[.creationDate] as? Date)
      ?? Date(timeIntervalSince1970: 0)
  )
  if lockFileAge < 2.0 {
    exit(0)
  }
}
try? "locked".write(toFile: lockPath, atomically: true, encoding: .utf8)  // Need a catch to exit silently without error?

// Hide cursor to prevent flickering
let cid = CGSMainConnectionID()
let hideKey = "SetsCursorInBackground" as CFString
_ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanTrue)
CGAssociateMouseAndMouseCursorPosition(0)
CGDisplayHideCursor(CGMainDisplayID())

// Trigger MenuWhere (command + right-click)
let mousePosition = CGEvent(source: nil)?.location ?? CGPoint.zero
let eventSource = CGEventSource(stateID: .combinedSessionState)
eventSource?.localEventsSuppressionInterval = 0.0

let resetRightMouseButton = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .rightMouseUp,
  mouseCursorPosition: mousePosition,
  mouseButton: .right
)
resetRightMouseButton?.post(tap: .cghidEventTap)
let resetLeftMouseButton = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .leftMouseUp,
  mouseCursorPosition: mousePosition,
  mouseButton: .left
)
resetLeftMouseButton?.post(tap: .cghidEventTap)
usleep(10000)

let moveToTarget = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: CGPoint(x: x, y: y),
  mouseButton: .left
)
moveToTarget?.post(tap: .cghidEventTap)
usleep(10000)

let mouseDown = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .rightMouseDown,
  mouseCursorPosition: CGPoint(x: x, y: y),
  mouseButton: .right
)
mouseDown?.flags = .maskCommand
mouseDown?.post(tap: .cghidEventTap)
usleep(10000)

let mouseUp = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .rightMouseUp,
  mouseCursorPosition: CGPoint(x: x, y: y),
  mouseButton: .right
)
mouseUp?.flags = .maskCommand
mouseUp?.post(tap: .cghidEventTap)
usleep(10000)

let moveBack = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: mousePosition,
  mouseButton: .left
)
moveBack?.post(tap: .cghidEventTap)
usleep(30000)  // Long delay here is necessary
