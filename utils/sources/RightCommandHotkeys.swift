// Shared: Accessibility Agent CGEvent CGEventFlags EventTap Log

import AppKit
import Carbon.HIToolbox

enum Configuration {
  static let subsystem = "industries.britown.RightCommandHotkeys"
  static let keymap = [
    CGKeyCode(kVK_ANSI_L): CGKeyCode(kVK_LeftArrow),
    CGKeyCode(kVK_ANSI_Quote): CGKeyCode(kVK_RightArrow),
    CGKeyCode(kVK_ANSI_P): CGKeyCode(kVK_UpArrow),
    CGKeyCode(kVK_ANSI_Semicolon): CGKeyCode(kVK_DownArrow),
    CGKeyCode(kVK_Return): CGKeyCode(kVK_Return)
  ]
}

@MainActor
final class HotkeyManager {
  private let startDate = Date.now
  private let keymap: [CGKeyCode: CGKeyCode]
  private let eventTap: EventTap
  private var activeHotkeys: [CGKeyCode: CGKeyCode] = [:]

  init(keymap: [CGKeyCode: CGKeyCode]) throws {
    self.keymap = keymap
    self.eventTap = try EventTap(location: .cgSessionEventTap, eventTypes: [.keyDown, .keyUp])

    eventTap.eventHandler = { [weak self] event in
      self?.handleEvent(event) ?? false
    }

    eventTap.interruptionHandler = { [weak self] in
      self?.releaseStaleHotkeys()
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
        Active hotkeys: \(activeHotkeys.count)
        Mapped hotkeys: \(keymap.count)
      """
    )
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    let keyCode = event.keyboardEventKeycode
    let isKeyDown = event.type == .keyDown

    let mappedKeyCode: CGKeyCode

    if !isKeyDown, let activeHotkey = activeHotkeys[keyCode] {
      activeHotkeys[keyCode] = nil
      mappedKeyCode = activeHotkey

    } else if isKeyDown, event.flags.contains(.maskRightCommand), let mappedCode = keymap[keyCode] {
      activeHotkeys[keyCode] = mappedCode
      mappedKeyCode = mappedCode

    } else {
      return false
    }

    return postMappedKeyEvent(keyCode: mappedKeyCode, isKeyDown: isKeyDown, flags: event.flags)
  }

  private func releaseStaleHotkeys() {
    let flags = CGEventSource.flagsState(.combinedSessionState)

    for (keyCode, mappedKeyCode) in activeHotkeys where !CGEventSource.keyState(.combinedSessionState, key: keyCode) {
      activeHotkeys[keyCode] = nil
      postMappedKeyEvent(keyCode: mappedKeyCode, isKeyDown: false, flags: flags)
    }
  }

  @discardableResult
  private func postMappedKeyEvent(keyCode: CGKeyCode, isKeyDown: Bool, flags: CGEventFlags) -> Bool {
    guard let mappedEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isKeyDown) else {
      return false
    }

    var mappedFlags = flags

    mappedFlags.remove(.maskRightCommand)

    if !flags.contains(.maskLeftCommand) {
      mappedFlags.remove(.maskCommand)
    }

    mappedEvent.flags = mappedFlags
    mappedEvent.post(tap: .cghidEventTap)

    return true
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var hotkeyManager: HotkeyManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.hotkeyManager = try HotkeyManager(keymap: Configuration.keymap)
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.hotkeyManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .printLog: hotkeyManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case printLog = "print-log"
  case quit
}

@main
enum RightCommandHotkeys {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
