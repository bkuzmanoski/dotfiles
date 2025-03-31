import ApplicationServices
import Cocoa
import EventKit
import Foundation

class SBEventProvider {
  static let shared = SBEventProvider()
  private init() {}

  private enum SBEvent: String {
    case appActivated = "app_activated"
    case windowTitleChanged = "window_title_changed"
    case calendarUpdated = "calendar_updated"

    var name: String { return self.rawValue }
  }

  private var appActivationObserver: NSObjectProtocol?
  private var eventStoreChangeObserver: NSObjectProtocol?
  private var eventStore = EKEventStore()

  private let appNotifications = [
    kAXMainWindowChangedNotification,
    kAXTitleChangedNotification,
    kAXWindowMiniaturizedNotification,
    kAXWindowDeminiaturizedNotification,
    kAXUIElementDestroyedNotification,
  ]
  private var activeApp: NSRunningApplication?
  private var mainWindowTitle: String?
  private var appObserver: AXObserver?
  private var appElement: AXUIElement?
  private var pendingStartAppObserverWorkItem: DispatchWorkItem?

  func start() {
    appActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: nil
    ) { [weak self] notification in self?.handleAppActivated(notification) }

    eventStoreChangeObserver = NotificationCenter.default.addObserver(
      forName: Notification.Name.EKEventStoreChanged, object: eventStore, queue: nil
    ) { [weak self] notification in self?.handleCalendarUpdated(notification) }

    handleAppActivated()
    handleCalendarUpdated()
  }

  func stop() {
    if let token = appActivationObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(token)
    }
    if let token = eventStoreChangeObserver {
      NotificationCenter.default.removeObserver(token)
    }
    stopAppObserver()
  }

  private func triggerEvent(_ event: String, parameters: [String] = []) {
    var args = ["--trigger", event]
    args.append(contentsOf: parameters)

    let task = Process()
    let pipe = Pipe()
    task.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/sketchybar")
    task.arguments = args
    task.standardOutput = pipe
    task.standardError = pipe

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

  // App change events

  private func handleAppActivated(_ notification: Notification? = nil) {
    guard
      let app = NSWorkspace.shared.menuBarOwningApplication,
      !app.isEqual(activeApp)
    else {
      return
    }

    let bundleId = app.bundleIdentifier ?? ""
    var name = app.localizedName ?? ""

    if let bundleURL = app.bundleURL, let bundle = Bundle(url: bundleURL),
      let bundleName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
      !bundleName.isEmpty
    {
      name = bundleName
    }

    guard !bundleId.isEmpty, !name.isEmpty else { return }

    pendingStartAppObserverWorkItem?.cancel()
    stopAppObserver()
    activeApp = app

    var parameters = [
      "BUNDLE_ID=\(bundleId)",
      "APP_NAME=\(name)",
    ]

    if let windowTitle = getWindowTitle(for: app) {
      mainWindowTitle = windowTitle
      parameters.append("WINDOW_TITLE=\(windowTitle)")
    }

    triggerEvent(SBEvent.appActivated.name, parameters: parameters)

    // Ensure app has finished launching before starting observer
    pendingStartAppObserverWorkItem = DispatchWorkItem { [weak self] in
      guard let self = self, app.isEqual(self.activeApp) else {
        return
      }
      self.startAppObserver()
      self.handleWindowTitleChanged()  // Update main window title in case it wasn't available immediately on launch
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: pendingStartAppObserverWorkItem!)
  }

  // Window title change events

  private func startAppObserver() {
    guard let app = activeApp else { return }
    let pid = app.processIdentifier
    appElement = AXUIElementCreateApplication(pid)
    guard let appElement = appElement else { return }

    AXObserverCreate(
      pid,
      { (_, _, notification, contextData) in
        let provider = Unmanaged<SBEventProvider>.fromOpaque(contextData!).takeUnretainedValue()
        provider.handleWindowTitleChanged()
      },
      &appObserver)

    if let appObserver = appObserver {
      let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
      for notification in appNotifications {
        AXObserverAddNotification(appObserver, appElement, notification as CFString, context)
      }
      CFRunLoopAddSource(
        CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(appObserver), .defaultMode)
    }
  }

  private func stopAppObserver() {
    guard let appObserver = appObserver, let appElement = appElement else { return }
    for notification in appNotifications {
      AXObserverRemoveNotification(appObserver, appElement, notification as CFString)
    }
    CFRunLoopRemoveSource(
      CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(appObserver), .defaultMode)
    self.appObserver = nil
    self.appElement = nil
  }

  private func handleWindowTitleChanged() {
    if let windowTitle = getWindowTitle() {
      if windowTitle != mainWindowTitle {
        mainWindowTitle = windowTitle
        triggerEvent(SBEvent.windowTitleChanged.name, parameters: ["WINDOW_TITLE=\(windowTitle)"])
      }
    } else if mainWindowTitle != nil {
      mainWindowTitle = nil
      triggerEvent(SBEvent.windowTitleChanged.name)
    }
  }

  private func getWindowTitle(for app: NSRunningApplication? = nil) -> String? {
    let (targetApp, targetAppElement): (NSRunningApplication, AXUIElement)

    if let activeApp = activeApp, let appElement = appElement {
      targetApp = activeApp
      targetAppElement = appElement
    } else if let providedApp = app {
      targetApp = providedApp
      targetAppElement = AXUIElementCreateApplication(providedApp.processIdentifier)
    } else {
      return nil
    }

    var mainWindow: AnyObject?
    let windowResult = AXUIElementCopyAttributeValue(
      targetAppElement, kAXMainWindowAttribute as CFString, &mainWindow)

    if windowResult == .success {
      let window = mainWindow as! AXUIElement
      var titleRef: AnyObject?
      let titleResult = AXUIElementCopyAttributeValue(
        window, kAXTitleAttribute as CFString, &titleRef)

      if titleResult == .success, let rawTitle = titleRef as? String {
        return formatWindowTitle(rawTitle, appName: targetApp.localizedName)
      }
    }

    return nil
  }

  private func formatWindowTitle(_ rawTitle: String, appName: String?) -> String? {
    guard !rawTitle.isEmpty else { return nil }

    var formattedTitle = rawTitle
    let maxLength = 50
    let escapedAppName = NSRegularExpression.escapedPattern(for: appName ?? "")
    let patternsToRemove = [
      // Activity Monitor (doesn't send kAXTitleChangedNotification when window title changes)
      "Activity Monitor.*",

      // Chrome
      " – Audio playing.*",
      " – Camera recording.*",
      " – Microphone recording.*",
      " – Camera and microphone recording.*",
      " - High memory usage.*",
      " - Google Chrome \\(Incognito\\)$",

      // Font Book
      " – \\d+( of \\d+)? typefaces$",

      // Mail
      " – \\d+(,\\d+)? (messages|drafts)(, *\\d+(,\\d+)? unread)?$",

      // Redundant app name
      "^\(escapedAppName)( [-–—] )?",
      "( [-–—] )?\(escapedAppName)$",
    ]

    for pattern in patternsToRemove {
      if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
        formattedTitle = regex.stringByReplacingMatches(
          in: formattedTitle,
          options: [],
          range: NSRange(location: 0, length: formattedTitle.utf16.count),
          withTemplate: "")
      }
    }

    return formattedTitle.prefix(maxLength).trimmingCharacters(in: .whitespaces)
      + (formattedTitle.count > maxLength ? "…" : "")
  }

  // Calendar update events

  private func handleCalendarUpdated(_ notification: Notification? = nil) {
    triggerEvent(SBEvent.calendarUpdated.name)
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

func exitGracefully() {
  SBEventProvider.shared.stop()
  exit(0)
}

signal(SIGHUP) { _ in exitGracefully() }
signal(SIGINT) { _ in exitGracefully() }
signal(SIGQUIT) { _ in exitGracefully() }
signal(SIGTERM) { _ in exitGracefully() }

SBEventProvider.shared.start()
RunLoop.main.run()
