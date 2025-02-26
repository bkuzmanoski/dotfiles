#!/usr/bin/swift

import ApplicationServices
import Cocoa
import Foundation

func setupSignalHandling() {
  signal(SIGINT) { sig in
    exit(0)
  }
  signal(SIGTERM) { sig in
    exit(0)
  }
}

func checkAccessibilityPermissions() -> Bool {
  let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
  let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
  return accessEnabled
}

func sendAppChangeEvent(bundleID: String, appName: String) {
  let task = Process()
  let pipe = Pipe()

  task.standardOutput = pipe
  task.standardError = pipe
  task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sketchybar")
  task.arguments = ["--trigger", "app_change", "BUNDLE_ID=\(bundleID)", "APP_NAME=\(appName)"]

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

func getMenuBarAppInfo() -> (bundleID: String, name: String) {
  if let menuBarApp = NSWorkspace.shared.menuBarOwningApplication {
    if let bundleID = menuBarApp.bundleIdentifier {
      var appName = ""
      if let appBundle = Bundle(url: menuBarApp.bundleURL!) {
        appName = appBundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? ""
      }
      if !appName.isEmpty {
        return (bundleID, appName)
      }
    }
  }
  return ("", "")
}

setupSignalHandling()

var lastBundleID = ""
var lastAppName = ""

let notificationCenter = NSWorkspace.shared.notificationCenter
notificationCenter.addObserver(
  forName: NSWorkspace.didActivateApplicationNotification,
  object: nil,
  queue: nil
) { notification in
  let (bundleID, appName) = getMenuBarAppInfo()
  if bundleID != lastBundleID || appName != lastAppName {
    lastBundleID = bundleID
    lastAppName = appName
    sendAppChangeEvent(bundleID: bundleID, appName: appName)
  }
}

let hasAccessibilityPermission = checkAccessibilityPermissions()
if !hasAccessibilityPermission {
  print("Accessibility Permission not granted")
  exit(1)
}

let (bundleID, appName) = getMenuBarAppInfo()
lastBundleID = bundleID
lastAppName = appName
sendAppChangeEvent(bundleID: bundleID, appName: appName)

RunLoop.main.run()
