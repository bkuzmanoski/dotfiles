#!/usr/bin/swift

import Cocoa
import Foundation

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int

@_silgen_name("CGSSetConnectionProperty")
func CGSSetConnectionProperty(_ cid: Int, _ ownerCid: Int, _ key: CFString, _ value: CFTypeRef) -> Int

func isMenuOpen() -> Bool {
  let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.manytricks.Menuwhere")
  guard !runningApps.isEmpty else {
    print("Info: MenuWhere is not running.")
    exit(0)
  }
  guard let windowListInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
  else {
    print("Error: Unable to retrieve window list.")
    exit(1)
  }
  for windowInfo in windowListInfo {
    if let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
      runningApps.contains(where: { $0.processIdentifier == ownerPID })
    {
      return true
    }
  }
  return false
}

guard CommandLine.arguments.count == 3,
  let x = Double(CommandLine.arguments[1]),
  let y = Double(CommandLine.arguments[2])
else {
  print("Usage: \(CommandLine.arguments[0]) x y")
  exit(1)
}

// If app menu is already open, let the click event close it
guard !isMenuOpen() else {
  exit(0)
}

// Hide cursor to hide visual jump
let cid = CGSMainConnectionID()
let hideKey = "SetsCursorInBackground" as CFString
_ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanTrue)
CGAssociateMouseAndMouseCursorPosition(0)
CGDisplayHideCursor(CGMainDisplayID())  //------------------------------------

defer {
  CGDisplayShowCursor(CGMainDisplayID())
  CGAssociateMouseAndMouseCursorPosition(1)
  _ = CGSSetConnectionProperty(cid, cid, hideKey, kCFBooleanFalse)
}

// Trigger MenuWhere (command + right-click)
let eventSource = CGEventSource(stateID: .combinedSessionState)
let cursorPosition = CGEvent(source: nil)?.location ?? CGPoint.zero
let clickTarget = CGPoint(x: x, y: y)  //------------------------------------

let mouseDown = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .rightMouseDown,
  mouseCursorPosition: clickTarget,
  mouseButton: .right
)
mouseDown?.flags = .maskCommand
mouseDown?.post(tap: .cghidEventTap)
usleep(10000)

let mouseUp = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .rightMouseUp,
  mouseCursorPosition: clickTarget,
  mouseButton: .right
)
mouseUp?.flags = .maskCommand
mouseUp?.post(tap: .cghidEventTap)
usleep(10000)

// Restore cursor to its original position and behavior
let moveBack = CGEvent(
  mouseEventSource: eventSource,
  mouseType: .mouseMoved,
  mouseCursorPosition: cursorPosition,
  mouseButton: .left
)
moveBack?.post(tap: .cghidEventTap)
