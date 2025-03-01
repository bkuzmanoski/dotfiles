import ApplicationServices
import Cocoa
import EventKit
import Foundation

// Helper for triggering Sketchybar events
func triggerEvent(_ event: String, parameters: [String] = []) {
  let task = Process()
  let pipe = Pipe()

  task.standardOutput = pipe
  task.standardError = pipe
  task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sketchybar")

  var args = ["--trigger", event]
  args.append(contentsOf: parameters)
  task.arguments = args

  do {
    try task.run()
    task.waitUntilExit()

    if task.terminationStatus != 0 {
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      if let output = String(data: data, encoding: .utf8) {
        print("Error: \(output)")
      }
    }
  } catch {
    print("Error: \(error)")
  }
}

// Check for Accessibility permissions
func checkAccessibilityPermissions() -> Bool {
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
  return AXIsProcessTrustedWithOptions(options as CFDictionary)
}

let hasAccessibilityPermission = checkAccessibilityPermissions()
if !hasAccessibilityPermission {
  print("Accessibility permission not granted.")
  exit(1)
}

// App change events
var lastBundleID = ""

func getMenuBarAppInfo() -> (bundleID: String, name: String) {
  guard let menuBarApp = NSWorkspace.shared.menuBarOwningApplication,
    let bundleID = menuBarApp.bundleIdentifier,
    let bundleURL = menuBarApp.bundleURL,
    let appBundle = Bundle(url: bundleURL),
    let appName = appBundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
    !appName.isEmpty
  else {
    return ("", "")
  }
  return (bundleID, appName)
}

let (initBundleID, initAppName) = getMenuBarAppInfo()
if !initBundleID.isEmpty {
  lastBundleID = initBundleID
  triggerEvent("app_change", parameters: ["BUNDLE_ID=\(initBundleID)", "APP_NAME=\(initAppName)"])
}

let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
let workspaceNotificationToken = workspaceNotificationCenter.addObserver(
  forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
) { _ in
  let (bundleID, appName) = getMenuBarAppInfo()
  if !bundleID.isEmpty && bundleID != lastBundleID {
    lastBundleID = bundleID
    triggerEvent("app_change", parameters: ["BUNDLE_ID=\(bundleID)", "APP_NAME=\(appName)"])
  }
}

// Event store change events
let eventStore = EKEventStore()
let calendarNotificationToken = NotificationCenter.default.addObserver(
  forName: Notification.Name.EKEventStoreChanged, object: eventStore, queue: nil
) { _ in
  triggerEvent("calendar_update")
}

// Clean up before exit
func cleanup() {
  workspaceNotificationCenter.removeObserver(workspaceNotificationToken)
  NotificationCenter.default.removeObserver(calendarNotificationToken)
  exit(0)
}

signal(SIGINT) { _ in cleanup() }
signal(SIGTERM) { _ in cleanup() }
signal(SIGHUP) { _ in cleanup() }

RunLoop.main.run()
