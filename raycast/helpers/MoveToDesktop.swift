import Cocoa
import Foundation

func getFocusedWindow() -> AXUIElement? {
  guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
    return nil
  }

  let pid = frontmostApp.processIdentifier
  let appElement = AXUIElementCreateApplication(pid)
  var focusedWindow: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(
    appElement,
    kAXFocusedWindowAttribute as CFString,
    &focusedWindow
  )

  if result != .success {
    return nil
  }

  return (focusedWindow as! AXUIElement)
}

func isStandardWindow(_ window: AXUIElement) -> Bool {
  var subrole: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)

  if result != .success {
    return false
  }

  if let subroleStr = subrole as? String {
    return subroleStr == "AXStandardWindow"
  }

  return false
}

func getWindowPosition(_ window: AXUIElement) -> NSPoint? {
  var position: CFTypeRef?
  let result = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position)

  if result != .success {
    return nil
  }

  var point = NSPoint()
  AXValueGetValue(position as! AXValue, .cgPoint, &point)
  return point
}

func performMouseAndKeyboardActions(at windowPosition: NSPoint, spaceNumber: Int) {
  let mousePosition = NSEvent.mouseLocation
  let adjustedMousePosition = CGPoint(
    x: mousePosition.x,
    y: NSScreen.main!.frame.height - mousePosition.y
  )
  let eventSource = CGEventSource(stateID: .combinedSessionState)
  let clickTarget = NSPoint(x: windowPosition.x + 5, y: windowPosition.y + 25)
  let keyCodeForNumber: [Int: CGKeyCode] = [
    1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25,
  ]

  guard let keyCode = keyCodeForNumber[spaceNumber] else {
    return
  }

  // Left mouse down
  let mouseDownEvent = CGEvent(
    mouseEventSource: eventSource,
    mouseType: .leftMouseDown,
    mouseCursorPosition: clickTarget,
    mouseButton: .left
  )
  mouseDownEvent?.post(tap: .cghidEventTap)
  usleep(100000)

  // Send Control + space number keystroke
  let keyDownEvent = CGEvent(
    keyboardEventSource: eventSource,
    virtualKey: keyCode,
    keyDown: true
  )
  keyDownEvent?.flags = .maskControl
  keyDownEvent?.post(tap: .cghidEventTap)

  let keyUpEvent = CGEvent(
    keyboardEventSource: eventSource,
    virtualKey: keyCode,
    keyDown: false
  )
  keyUpEvent?.post(tap: .cghidEventTap)
  usleep(100000)

  // Left mouse up
  let mouseUpEvent = CGEvent(
    mouseEventSource: eventSource,
    mouseType: .leftMouseUp,
    mouseCursorPosition: clickTarget,
    mouseButton: .left
  )
  mouseUpEvent?.post(tap: .cghidEventTap)

  // Return the mouse cursor back to its original position
  CGWarpMouseCursorPosition(adjustedMousePosition)
}

func parseSpacesConfig() -> (totalSpaces: Int, currentSpaceIndex: Int)? {
  let homePath = NSHomeDirectory()
  let plistPath = "\(homePath)/Library/Preferences/com.apple.spaces.plist"

  guard FileManager.default.fileExists(atPath: plistPath) else {
    return nil
  }

  guard let plistData = try? Data(contentsOf: URL(fileURLWithPath: plistPath)) else {
    return nil
  }

  var plistFormat = PropertyListSerialization.PropertyListFormat.xml
  guard
    let plist = try? PropertyListSerialization.propertyList(
      from: plistData,
      options: .mutableContainersAndLeaves,
      format: &plistFormat) as? [String: Any]
  else {
    return nil
  }

  guard
    let displayConfig = plist["SpacesDisplayConfiguration"] as? [String: Any],
    let managementData = displayConfig["Management Data"] as? [String: Any],
    let monitors = managementData["Monitors"] as? [[String: Any]],
    let mainDisplay = monitors.first,  // TODO: Find display where "Display Identifier" => "Main"
    let currentSpaceData = mainDisplay["Current Space"] as? [String: Any],
    let currentSpaceID = currentSpaceData["ManagedSpaceID"] as? Int,
    let spacesArray = mainDisplay["Spaces"] as? [[String: Any]]
  else {
    return nil
  }

  // Filter spaces with type = 0 (normal spaces)
  let normalSpaces = spacesArray.filter { space in
    guard let type = space["type"] as? Int else { return false }
    return type == 0
  }

  // Find the index of the current space in the list of normal spaces
  var currentIndex = -1  // TODO: Fix this for left/right
  for (index, space) in normalSpaces.enumerated() {
    guard let spaceID = space["ManagedSpaceID"] as? Int else { continue }
    if spaceID == currentSpaceID {
      currentIndex = index
      break
    }
  }

  guard currentIndex >= 0 else {
    return nil
  }

  // Adding 1 to convert to 1-indexed
  return (normalSpaces.count, currentIndex + 1)
}

func printUsage() {
  print("Usage: \(CommandLine.arguments[0]) [left|right|1-9]")
}

// TODO: Create a lockfile to prevent multiple instances of the script from running at the same time

guard CommandLine.arguments.count > 1 else {
  printUsage()
  exit(1)
}

let argument = CommandLine.arguments[1].lowercased()

// Get the focused window
guard let focusedWindow = getFocusedWindow() else {
  print("No focused window found")
  exit(1)
}

// Check if it's a standard window (not the desktop, a dialog, a menu, etc.)
guard isStandardWindow(focusedWindow) else {
  exit(0)
}

// Get window position
guard let position = getWindowPosition(focusedWindow) else {
  print("Couldn't get window position")
  exit(1)
}

// Handle arguments
if let targetSpace = Int(argument), (1...9).contains(targetSpace) {
  // Direct space selection with number
  performMouseAndKeyboardActions(at: position, spaceNumber: targetSpace)
} else if argument == "left" || argument == "right" {
  // Relative space navigation (less buggy than Raycast's built-in "Move to Desktop" commands)
  guard let (totalSpaces, currentSpaceIndex) = parseSpacesConfig() else {
    print("Couldn't get available desktops")
    exit(1)
  }

  var targetSpace: Int

  if argument == "left" {
    targetSpace = currentSpaceIndex - 1
    if targetSpace < 1 {
      targetSpace = totalSpaces
    }
  } else if argument == "right" {
    targetSpace = currentSpaceIndex + 1
    if targetSpace > totalSpaces {
      targetSpace = 1
    }
  } else {
    print("Invalid argument: \(argument)")
    printUsage()
    exit(1)
  }

  performMouseAndKeyboardActions(at: position, spaceNumber: targetSpace)
} else {
  print("Invalid argument: \(argument)")
  printUsage()
  exit(1)
}
