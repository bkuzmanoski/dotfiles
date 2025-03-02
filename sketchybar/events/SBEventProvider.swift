import ApplicationServices
import Cocoa
import EventKit
import Foundation

struct SBEvent {
  static let appChange = "app_change"
  static let calendarUpdate = "calendar_update"
}

var execPath = "/opt/homebrew/bin/sketchybar"
var triggerDelay: Double = 0.0

func usage() {
  let progName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "SBEventProvider"
  print(
    """
    Usage: \(progName) [--sketchybar <path>] [--delay <seconds>]

      --sketchybar    Path to the sketchybar executable. Default: /opt/homebrew/bin/sketchybar.
      --delay         Delay (in seconds) before the initial \(SBEvent.appChange) event trigger. Default: 0.
    """)
}

func parseArguments() {
  var iterator = CommandLine.arguments.dropFirst().makeIterator()

  while let arg = iterator.next() {
    switch arg {
    case "--sketchybar":
      guard let value = iterator.next() else {
        usage()
        exit(1)
      }
      execPath = value

    case "--delay":
      guard let value = iterator.next(), let delay = Double(value) else {
        usage()
        exit(1)
      }
      triggerDelay = delay

    default:
      usage()
      exit(1)
    }
  }
}
parseArguments()

func triggerEvent(_ event: String, parameters: [String] = []) {
  let task = Process()
  let pipe = Pipe()

  task.standardOutput = pipe
  task.standardError = pipe
  task.executableURL = URL(fileURLWithPath: execPath)

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

func checkAccessibilityPermissions() -> Bool {
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
  return AXIsProcessTrustedWithOptions(options as CFDictionary)
}

guard checkAccessibilityPermissions() else {
  print("Accessibility permission not granted.")
  exit(1)
}

var lastBundleID = ""

func getMenuBarAppInfo() -> (bundleID: String, name: String) {
  guard
    let menuBarApp = NSWorkspace.shared.menuBarOwningApplication,
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
  DispatchQueue.main.asyncAfter(deadline: .now() + triggerDelay) {
    lastBundleID = initBundleID
    triggerEvent(
      SBEvent.appChange,
      parameters: [
        "BUNDLE_ID=\(initBundleID)",
        "APP_NAME=\(initAppName)",
      ])
  }
}

let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
let workspaceNotificationToken = workspaceNotificationCenter.addObserver(
  forName: NSWorkspace.didActivateApplicationNotification,
  object: nil,
  queue: nil
) { _ in
  let (bundleID, appName) = getMenuBarAppInfo()
  if !bundleID.isEmpty && bundleID != lastBundleID {
    lastBundleID = bundleID
    triggerEvent(
      SBEvent.appChange,
      parameters: [
        "BUNDLE_ID=\(bundleID)",
        "APP_NAME=\(appName)",
      ])
  }
}

let eventStore = EKEventStore()
let calendarNotificationToken = NotificationCenter.default.addObserver(
  forName: Notification.Name.EKEventStoreChanged,
  object: eventStore,
  queue: nil
) { _ in
  triggerEvent(SBEvent.calendarUpdate)
}

func cleanup() {
  workspaceNotificationCenter.removeObserver(workspaceNotificationToken)
  NotificationCenter.default.removeObserver(calendarNotificationToken)
  exit(0)
}

signal(SIGINT) { _ in cleanup() }
signal(SIGTERM) { _ in cleanup() }
signal(SIGHUP) { _ in cleanup() }

RunLoop.main.run()
