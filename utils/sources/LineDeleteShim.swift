// Shared: Accessibility Agent CGEvent CGEventFlags EventTap Log

import AppKit
import Carbon.HIToolbox

enum Configuration {
  static let subsystem = "industries.britown.LineDeleteShim"
  static let targetBundleIdentifiers: Set<String> = ["com.raycast.macos"]
  static let fallbackKeyRepeatInterval = 6
  static let fallbackKeyRepeatInitialDelay = 25
}

struct KeyRepeatSettings {
  private static let tick: Duration = .nanoseconds(1_000_000_000 / 60)

  let initialDelay: Duration
  let interval: Duration

  init(userDefaults: UserDefaults = .standard) {
    self.initialDelay =
      Self.tick
      * Self.ticks(
        forKey: "InitialKeyRepeat",
        fallback: Configuration.fallbackKeyRepeatInitialDelay,
        userDefaults: userDefaults
      )
    self.interval =
      Self.tick
      * Self.ticks(forKey: "KeyRepeat", fallback: Configuration.fallbackKeyRepeatInterval, userDefaults: userDefaults)
  }

  private static func ticks(forKey key: String, fallback: Int, userDefaults: UserDefaults = .standard) -> Int {
    guard let value = userDefaults.object(forKey: key) as? Int, value > 0 else {
      return fallback
    }

    return value
  }
}

@MainActor
final class LineDeleteManager {
  private let startDate = Date.now
  private let synthesizedEventMarker: Int64 = 0x4c44_4744
  private let eventSettlingDelay: Duration = .milliseconds(30)
  private let targetBundleIdentifiers: Set<String>
  private let keyRepeatSettings: KeyRepeatSettings
  private let effectiveKeyRepeatInterval: Duration
  private let delayBeforeFirstRepeat: Duration
  private let delayBetweenRepeats: Duration
  private let eventTap: EventTap
  private var keyRepeatTask: Task<Void, Never>?

  private var isTargetApplicationFocused: Bool {
    do {
      guard
        let bundleIdentifier = try AXUIElement.focusedApplicationBundleIdentifier()
          ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      else {
        return false
      }

      return targetBundleIdentifiers.contains(bundleIdentifier)
    } catch {
      Log.error("Failed to retrieve focused application bundle identifier: \(error.localizedDescription)")
      return false
    }
  }

  init(targetBundleIdentifiers: Set<String>, keyRepeatSettings: KeyRepeatSettings) throws {
    self.targetBundleIdentifiers = targetBundleIdentifiers
    self.keyRepeatSettings = keyRepeatSettings
    self.effectiveKeyRepeatInterval = max(keyRepeatSettings.interval, eventSettlingDelay * 2)
    self.delayBeforeFirstRepeat = max(
      eventSettlingDelay,
      keyRepeatSettings.initialDelay - eventSettlingDelay
    )
    self.delayBetweenRepeats = effectiveKeyRepeatInterval - eventSettlingDelay
    self.eventTap = try EventTap(location: .cgSessionEventTap, eventTypes: [.keyDown, .keyUp])

    AXUIElement.setGlobalMessagingTimeout(seconds: 0.05)

    eventTap.eventHandler = { [weak self] event in
      self?.handleEvent(event) ?? false
    }

    eventTap.interruptionHandler = { [weak self] in
      self?.stopPerformingKeySequences()
    }

    eventTap.isEnabled = true
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AccessibilityPermission.isGranted)
        Event tap active: \(eventTap.isActive)
        Target app focused: \(isTargetApplicationFocused)
        Performing key sequences: \(keyRepeatTask != nil)
        Target bundle IDs: \(targetBundleIdentifiers.sorted().joined(separator: ", "))
        Key repeat:
          Initial delay: \(keyRepeatSettings.initialDelay) (system)
          Interval: \(effectiveKeyRepeatInterval) (system: \(keyRepeatSettings.interval))
        Key sequence:
          Settling delay: \(eventSettlingDelay)
          Delay before first repeat: \(delayBeforeFirstRepeat)
          Delay between repeats: \(delayBetweenRepeats)
      """
    )
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    guard
      event.eventSourceUserData != synthesizedEventMarker,
      event.keyboardEventKeycode == CGKeyCode(kVK_Delete)
    else {
      return false
    }

    guard event.type == .keyDown else {
      guard keyRepeatTask != nil else {
        return false
      }

      stopPerformingKeySequences()

      return true
    }

    guard event.flags.intersection(.modifierFlagsMask) == .maskCommand else {
      stopPerformingKeySequences()
      return false
    }

    guard !event.keyboardEventAutorepeat else {
      return keyRepeatTask != nil
    }

    guard isTargetApplicationFocused else {
      return false
    }

    startPerformingKeySequences()

    return true
  }

  private func startPerformingKeySequences() {
    keyRepeatTask?.cancel()
    self.keyRepeatTask = Task {
      guard await performKeySequence() else {
        return
      }

      do {
        try await Task.sleep(for: delayBeforeFirstRepeat)

        while !Task.isCancelled {
          guard await performKeySequence() else {
            return
          }

          try await Task.sleep(for: delayBetweenRepeats)
        }
      } catch {
        return
      }
    }
  }

  private func stopPerformingKeySequences() {
    keyRepeatTask?.cancel()
    keyRepeatTask = nil
  }

  private func performKeySequence() async -> Bool {
    guard postEvent(virtualKey: CGKeyCode(kVK_LeftArrow), flags: [.maskCommand, .maskShift]) else {
      Log.error("Failed to synthesize selection event.")
      return false
    }

    try? await Task.sleep(for: eventSettlingDelay)

    guard postEvent(virtualKey: CGKeyCode(kVK_Delete), flags: []) else {
      Log.error("Failed to synthesize delete event.")
      return false
    }

    return true
  }

  private func postEvent(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
    let events = [true, false].compactMap { isKeyDown in
      CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: isKeyDown)
    }

    guard events.count == 2 else {
      return false
    }

    for event in events {
      event.flags = flags
      event.eventSourceUserData = synthesizedEventMarker
      event.post(tap: .cghidEventTap)
    }

    return true
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var lineDeleteManager: LineDeleteManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.lineDeleteManager = try LineDeleteManager(
        targetBundleIdentifiers: Configuration.targetBundleIdentifiers,
        keyRepeatSettings: KeyRepeatSettings()
      )
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.lineDeleteManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .printLog: lineDeleteManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case printLog = "print-log"
  case quit
}

@main
enum LineDeleteShim {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
