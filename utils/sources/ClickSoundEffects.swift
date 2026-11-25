// Shared: Accessibility Agent AudioDevice CGEvent EventTap Log

import AppKit
import AudioToolbox

enum Configuration {
  static let subsystem = "industries.britown.ClickSoundEffects"
  static let soundFileDirectoryPath = "~/.dotfiles/utils/assets"
}

enum SoundEffect: CaseIterable, CustomStringConvertible {
  case leftClickDown
  case leftClickUp
  case rightClickDown
  case rightClickUp

  var fileName: String {
    switch self {
    case .leftClickDown: return "left-click-down.wav"
    case .leftClickUp: return "left-click-up.wav"
    case .rightClickDown: return "right-click-down.wav"
    case .rightClickUp: return "right-click-up.wav"
    }
  }

  var description: String {
    switch self {
    case .leftClickDown: return "Left Click Down"
    case .leftClickUp: return "Left Click Up"
    case .rightClickDown: return "Right Click Down"
    case .rightClickUp: return "Right Click Up"
    }
  }
}

final class SoundEffectManager {
  enum Error: Swift.Error, LocalizedError {
    case soundFileDirectoryNotFound(path: String)
    case invalidSoundFileDirectoryPath(String)
    case soundFileNotFound(soundEffect: SoundEffect, path: String)

    var errorDescription: String? {
      switch self {
      case .soundFileDirectoryNotFound(let path): "Sound file directory not found at path: \(path)"
      case .invalidSoundFileDirectoryPath(let path): "Invalid sound file directory path (not a directory): \(path)"
      case .soundFileNotFound(let soundEffect, let path): "Sound file for '\(soundEffect)' not found at path: \(path)"
      }
    }
  }

  private let systemSoundIDs: [SoundEffect: SystemSoundID]

  init(soundFileDirectoryURL: URL) throws {
    guard FileManager.default.fileExists(atPath: soundFileDirectoryURL.path(percentEncoded: false)) else {
      throw Error.soundFileDirectoryNotFound(path: soundFileDirectoryURL.path(percentEncoded: false))
    }

    guard soundFileDirectoryURL.hasDirectoryPath else {
      throw Error.invalidSoundFileDirectoryPath(soundFileDirectoryURL.path(percentEncoded: false))
    }

    var systemSoundIDs: [SoundEffect: SystemSoundID] = [:]

    do {
      for soundEffect in SoundEffect.allCases {
        systemSoundIDs[soundEffect] = try Self.load(soundEffect: soundEffect, from: soundFileDirectoryURL)
      }
    } catch {
      Self.dispose(systemSoundIDs: systemSoundIDs)
      throw error
    }

    self.systemSoundIDs = systemSoundIDs
  }

  deinit {
    Self.dispose(systemSoundIDs: systemSoundIDs)
  }

  func play(soundEffect: SoundEffect) {
    guard let soundID = systemSoundIDs[soundEffect] else {
      return
    }

    AudioServicesPlaySystemSound(soundID)
  }

  private static func load(soundEffect: SoundEffect, from soundFileDirectoryURL: URL) throws -> SystemSoundID {
    let soundURL = soundFileDirectoryURL.appending(path: soundEffect.fileName)

    guard FileManager.default.fileExists(atPath: soundURL.path(percentEncoded: false)) else {
      throw Error.soundFileNotFound(soundEffect: soundEffect, path: soundURL.path(percentEncoded: false))
    }

    var soundID: SystemSoundID = 0

    AudioServicesCreateSystemSoundID(soundURL as CFURL, &soundID)

    return soundID
  }

  private static func dispose(systemSoundIDs: [SoundEffect: SystemSoundID]) {
    for soundID in systemSoundIDs.values {
      AudioServicesDisposeSystemSoundID(soundID)
    }
  }
}

@MainActor
final class ClickMonitor {
  private(set) var isEnabled = true
  private(set) var isSuspended: Bool

  private let startDate = Date.now
  private let soundEffectManager: SoundEffectManager
  private let eventTap: EventTap

  init(soundEffectManager: SoundEffectManager, isSuspended: Bool) throws {
    self.soundEffectManager = soundEffectManager
    self.isSuspended = isSuspended
    self.eventTap = try EventTap(
      location: .cghidEventTap,
      observing: [.leftMouseDown, .leftMouseUp, .otherMouseDown, .otherMouseUp, .rightMouseDown, .rightMouseUp]
    )

    eventTap.eventObserver = { [weak self] event in
      self?.handleEvent(event)
    }

    updateEventTapState()
  }

  func toggleEnabled() {
    self.isEnabled.toggle()
    updateEventTapState()
  }

  func setSuspended(_ isSuspended: Bool) {
    guard self.isSuspended != isSuspended else {
      return
    }

    self.isSuspended = isSuspended

    updateEventTapState()
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AccessibilityPermission.isGranted)
        Enabled: \(isEnabled)
        Event tap active: \(eventTap.isActive)
        Event tap Mach port valid: \(eventTap.isMachPortValid)
        Suspended: \(isSuspended)
      """
    )
  }

  private func updateEventTapState() {
    eventTap.isEnabled = isEnabled && !isSuspended
  }

  private func handleEvent(_ event: CGEvent) {
    guard event.mouseEventSubtype == .touch else {
      return
    }

    switch event.type {
    case .leftMouseDown:
      soundEffectManager.play(soundEffect: .leftClickDown)

    case .leftMouseUp:
      soundEffectManager.play(soundEffect: .leftClickUp)

    case .otherMouseDown, .rightMouseDown:
      soundEffectManager.play(soundEffect: .rightClickDown)

    case .otherMouseUp, .rightMouseUp:
      soundEffectManager.play(soundEffect: .rightClickUp)

    default:
      break
    }
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var clickMonitor: ClickMonitor?
  private var systemOutputDeviceObservationTask: Task<Void, Never>?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let defaultSystemOutputDeviceUpdates = try AudioDevice.defaultDeviceUpdates(for: .systemOutput)
      let soundEffectManager = try SoundEffectManager(
        soundFileDirectoryURL: URL(filePath: Configuration.soundFileDirectoryPath, directoryHint: .isDirectory)
      )
      let clickMonitor = try ClickMonitor(
        soundEffectManager: soundEffectManager,
        isSuspended: true
      )

      self.clickMonitor = clickMonitor
      self.systemOutputDeviceObservationTask = Task {
        for await defaultSystemOutputDevice in defaultSystemOutputDeviceUpdates {
          do {
            clickMonitor.setSuspended(try defaultSystemOutputDevice?.transportType.isBluetooth ?? true)
          } catch {
            Log.error(error.localizedDescription)
          }
        }
      }
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    systemOutputDeviceObservationTask?.cancel()

    self.systemOutputDeviceObservationTask = nil
    self.clickMonitor = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .toggle: clickMonitor?.toggleEnabled()
    case .printLog: clickMonitor?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case toggle
  case printLog = "print-log"
  case quit
}

@main
enum ClickSoundEffects {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
