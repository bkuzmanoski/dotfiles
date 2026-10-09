// Shared: Accessibility Agent CGEvent EventTap Log

import AppKit
import AudioToolbox

enum Configuration {
  static let subsystem = "industries.britown.ClickSoundEffects"
  static let soundFileDirectoryPath = "~/.dotfiles/utils/assets"
}

typealias AudioDeviceTransportType = UInt32

extension AudioDeviceTransportType {
  var isBluetooth: Bool { self == kAudioDeviceTransportTypeBluetooth || self == kAudioDeviceTransportTypeBluetoothLE }
}

extension OSStatus {
  var fourCharCodeString: String? {
    let bytes = [
      UInt8((self >> 24) & 0xff),
      UInt8((self >> 16) & 0xff),
      UInt8((self >> 8) & 0xff),
      UInt8(self & 0xff)
    ]

    guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }) else {
      return nil
    }

    let scalars = bytes.compactMap { UnicodeScalar($0) }

    return String(String.UnicodeScalarView(scalars))
  }

  var statusDescription: String { fourCharCodeString.map { "\($0) (\(self))" } ?? String(self) }
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
      options: .listenOnly,
      eventTypes: [.leftMouseDown, .leftMouseUp, .otherMouseDown, .otherMouseUp, .rightMouseDown, .rightMouseUp]
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

final class SystemOutputDeviceObserver {
  enum Error: Swift.Error, LocalizedError {
    case failedToDetermineOutputDevice(status: OSStatus)
    case failedToDetermineDeviceTransportType(deviceID: AudioObjectID, status: OSStatus)
    case failedToObserveOutputDeviceChanges(status: OSStatus)

    var errorDescription: String? {
      switch self {
      case .failedToDetermineOutputDevice(let status):
        "Failed to determine the output audio device: \(status.statusDescription)"

      case .failedToDetermineDeviceTransportType(let deviceID, let status):
        "Failed to determine the transport type for device '\(deviceID)': \(status.statusDescription)"

      case .failedToObserveOutputDeviceChanges(let status):
        "Failed to observe output device changes: \(status.statusDescription)"
      }
    }
  }

  private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
  private let defaultSystemOutputDevicePropertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  private let transportTypePropertyAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyTransportType,
    mScope: kAudioObjectPropertyScopeGlobal,
    mElement: kAudioObjectPropertyElementMain
  )
  private let onTransportTypeChanged: (AudioDeviceTransportType) -> Void
  private lazy var systemOutputDevicePropertyListenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
    self?.handleOutputDeviceChanged()
  }

  init(onTransportTypeChanged: @escaping (AudioDeviceTransportType) -> Void) throws {
    self.onTransportTypeChanged = onTransportTypeChanged

    var defaultSystemOutputDevicePropertyAddress = defaultSystemOutputDevicePropertyAddress

    let status = AudioObjectAddPropertyListenerBlock(
      systemObjectID,
      &defaultSystemOutputDevicePropertyAddress,
      .main,
      systemOutputDevicePropertyListenerBlock
    )

    guard status == kAudioHardwareNoError else {
      throw Error.failedToObserveOutputDeviceChanges(status: status)
    }
  }

  deinit {
    var defaultSystemOutputDevicePropertyAddress = defaultSystemOutputDevicePropertyAddress
    AudioObjectRemovePropertyListenerBlock(
      systemObjectID,
      &defaultSystemOutputDevicePropertyAddress,
      .main,
      systemOutputDevicePropertyListenerBlock
    )
  }

  func currentTransportType() throws -> AudioDeviceTransportType {
    var defaultSystemOutputDevicePropertyAddress = defaultSystemOutputDevicePropertyAddress
    var defaultSystemOutputDeviceID = kAudioObjectUnknown
    var defaultSystemOutputDevicePropertyDataSize = UInt32(MemoryLayout.size(ofValue: defaultSystemOutputDeviceID))

    let getDefaultSystemOutputDevicePropertyStatus = AudioObjectGetPropertyData(
      systemObjectID,
      &defaultSystemOutputDevicePropertyAddress,
      0,
      nil,
      &defaultSystemOutputDevicePropertyDataSize,
      &defaultSystemOutputDeviceID
    )

    guard
      getDefaultSystemOutputDevicePropertyStatus == kAudioHardwareNoError,
      defaultSystemOutputDeviceID != kAudioObjectUnknown
    else {
      throw Error.failedToDetermineOutputDevice(status: getDefaultSystemOutputDevicePropertyStatus)
    }

    var transportTypePropertyAddress = transportTypePropertyAddress

    guard AudioObjectHasProperty(defaultSystemOutputDeviceID, &transportTypePropertyAddress) else {
      return kAudioDeviceTransportTypeUnknown
    }

    var transportType = kAudioDeviceTransportTypeUnknown
    var transportTypePropertyDataSize = UInt32(MemoryLayout.size(ofValue: transportType))

    let getTransportTypePropertyStatus = AudioObjectGetPropertyData(
      defaultSystemOutputDeviceID,
      &transportTypePropertyAddress,
      0,
      nil,
      &transportTypePropertyDataSize,
      &transportType
    )

    guard getTransportTypePropertyStatus == kAudioHardwareNoError else {
      throw Error.failedToDetermineDeviceTransportType(
        deviceID: defaultSystemOutputDeviceID,
        status: getTransportTypePropertyStatus
      )
    }

    return transportType
  }

  private func handleOutputDeviceChanged() {
    let transportType: AudioDeviceTransportType

    do {
      transportType = try currentTransportType()
    } catch {
      Log.error(error.localizedDescription)
      transportType = kAudioDeviceTransportTypeUnknown
    }

    onTransportTypeChanged(transportType)
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var systemOutputDeviceObserver: SystemOutputDeviceObserver?
  private var clickMonitor: ClickMonitor?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let systemOutputDeviceObserver = try SystemOutputDeviceObserver { [weak self] transportType in
        self?.clickMonitor?.setSuspended(transportType.isBluetooth)
      }

      let soundEffectManager = try SoundEffectManager(
        soundFileDirectoryURL: URL(filePath: Configuration.soundFileDirectoryPath, directoryHint: .isDirectory)
      )
      let clickMonitor = try ClickMonitor(
        soundEffectManager: soundEffectManager,
        isSuspended: systemOutputDeviceObserver.currentTransportType().isBluetooth
      )

      self.systemOutputDeviceObserver = systemOutputDeviceObserver
      self.clickMonitor = clickMonitor
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.systemOutputDeviceObserver = nil
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
