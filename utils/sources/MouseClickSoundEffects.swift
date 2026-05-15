import AppKit
import AudioToolbox

enum Constants {
  static let subsystem = "industries.britown.MouseClickSoundEffects"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let soundFileDirectory = "~/.dotfiles/utils/assets"
}

enum ProcessSignals {
  static func stream(for signals: [CInt]) -> AsyncStream<CInt> {
    let sources = signals.map { signal in
      DispatchSource.makeSignalSource(signal: signal, queue: .main)
    }

    let (stream, continuation) = AsyncStream.makeStream(of: CInt.self)

    for (signal, source) in zip(signals, sources) {
      source.setEventHandler {
        continuation.yield(signal)
      }

      source.resume()
    }

    continuation.onTermination = { _ in
      sources.forEach { source in
        source.cancel()
      }
    }

    return stream
  }
}

struct Command {
  let arguments: [String]

  func send() {
    DistributedNotificationCenter.default().postNotificationName(
      Constants.notificationName,
      object: nil,
      userInfo: [Constants.notificationUserInfoKey: arguments],
      deliverImmediately: true
    )
  }
}

final class SingleInstanceLock {
  enum Error: Swift.Error, LocalizedError {
    case instanceAlreadyRunning
    case failedToAcquireLock(errno: Int32)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: return "Instance already running."
      case .failedToAcquireLock(let errno): return "Failed to acquire lock (\(String(cString: strerror(errno))))."
      }
    }
  }

  private let lockFilePath = FileManager.default.temporaryDirectory.appendingPathComponent(Constants.lockFileName).path
  private var lockFileDescriptor: CInt

  init() throws {
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)

    guard fd != -1 else {
      throw Error.failedToAcquireLock(errno: errno)
    }

    guard flock(fd, LOCK_EX | LOCK_NB) != -1 else {
      close(fd)

      guard errno == EWOULDBLOCK else {
        throw Error.failedToAcquireLock(errno: errno)
      }

      throw Error.instanceAlreadyRunning
    }

    self.lockFileDescriptor = fd
  }

  deinit {
    flock(lockFileDescriptor, LOCK_UN)
    close(lockFileDescriptor)

    try? FileManager.default.removeItem(atPath: lockFilePath)
  }
}

enum SoundEffect: CaseIterable, CustomStringConvertible {
  case leftMouseDown
  case leftMouseUp
  case rightMouseDown
  case rightMouseUp

  var fileName: String {
    switch self {
    case .leftMouseDown: return "left-mouse-click-down.wav"
    case .leftMouseUp: return "left-mouse-click-up.wav"
    case .rightMouseDown: return "right-mouse-click-down.wav"
    case .rightMouseUp: return "right-mouse-click-up.wav"
    }
  }

  var description: String {
    switch self {
    case .leftMouseDown: return "Left Mouse Click Down"
    case .leftMouseUp: return "Left Mouse Click Up"
    case .rightMouseDown: return "Right Mouse Click Down"
    case .rightMouseUp: return "Right Mouse Click Up"
    }
  }
}

final class SoundEffectManager {
  enum Error: Swift.Error, LocalizedError {
    case soundFileNotFound(soundEffect: SoundEffect, path: String)

    var errorDescription: String? {
      switch self {
      case .soundFileNotFound(let soundEffect, let path): "Sound file for \(soundEffect) not found at path: \(path)"
      }
    }
  }

  private let systemSoundIDs: [SoundEffect: SystemSoundID]

  init() throws {
    let soundFileDirectoryPath = NSString(string: Constants.soundFileDirectory).expandingTildeInPath
    let soundFileDirectoryURL = URL(fileURLWithPath: soundFileDirectoryPath, isDirectory: true)

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
    let soundURL = soundFileDirectoryURL.appendingPathComponent(soundEffect.fileName)

    guard FileManager.default.fileExists(atPath: soundURL.path) else {
      throw Error.soundFileNotFound(soundEffect: soundEffect, path: soundURL.path)
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
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionNotGranted
    case failedToCreateEventTap

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionNotGranted: return "Accessibility permission not granted."
      case .failedToCreateEventTap: return "Failed to create event tap."
      }
    }
  }

  private(set) var isEnabled = true
  private(set) var isSuspended: Bool

  private let soundEffectManager: SoundEffectManager
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init(soundEffectManager: SoundEffectManager, isSuspended: Bool) throws {
    self.soundEffectManager = soundEffectManager
    self.isSuspended = isSuspended

    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: 1 << CGEventType.leftMouseDown.rawValue
          | 1 << CGEventType.leftMouseUp.rawValue
          | 1 << CGEventType.otherMouseDown.rawValue
          | 1 << CGEventType.otherMouseUp.rawValue
          | 1 << CGEventType.rightMouseDown.rawValue
          | 1 << CGEventType.rightMouseUp.rawValue,
        callback: { _, type, event, refcon in
          if let refcon {
            Unmanaged<ClickMonitor>.fromOpaque(refcon).takeUnretainedValue().handleEvent(ofType: type)
          }

          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource

    updateEventTapState()
  }

  deinit {
    if let eventTap {
      if CGEvent.tapIsEnabled(tap: eventTap) {
        CGEvent.tapEnable(tap: eventTap, enable: false)
      }

      CFMachPortInvalidate(eventTap)
    }

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
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

  private func updateEventTapState() {
    guard let eventTap else {
      return
    }

    let shouldEnable = isEnabled && !isSuspended

    guard CGEvent.tapIsEnabled(tap: eventTap) != shouldEnable else {
      return
    }

    CGEvent.tapEnable(tap: eventTap, enable: shouldEnable)
  }

  private func handleEvent(ofType type: CGEventType) {
    switch type {
    case .leftMouseDown:
      soundEffectManager.play(soundEffect: .leftMouseDown)

    case .leftMouseUp:
      soundEffectManager.play(soundEffect: .leftMouseUp)

    case .otherMouseDown, .rightMouseDown:
      soundEffectManager.play(soundEffect: .rightMouseDown)

    case .otherMouseUp, .rightMouseUp:
      soundEffectManager.play(soundEffect: .rightMouseUp)

    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      updateEventTapState()

    default:
      break
    }
  }
}

typealias AudioDeviceTransportType = UInt32

extension AudioDeviceTransportType {
  var isBluetooth: Bool { self == kAudioDeviceTransportTypeBluetooth || self == kAudioDeviceTransportTypeBluetoothLE }
}

final class OutputDeviceObserver {
  enum Error: Swift.Error, LocalizedError {
    case failedToDetermineOutputDevice(status: OSStatus)
    case failedToDetermineDeviceTransportType(deviceID: AudioObjectID, status: OSStatus)
    case failedToObserveOutputDeviceChanges(status: OSStatus)

    var errorDescription: String? {
      switch self {
      case .failedToDetermineOutputDevice(let status):
        "Failed to determine the output audio device (\(status))."

      case .failedToDetermineDeviceTransportType(let deviceID, let status):
        "Failed to determine the transport type for device \(deviceID) (\(status))."

      case .failedToObserveOutputDeviceChanges(let status):
        "Failed to observe output device changes (\(status))."
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
  private lazy var defaultSystemOutputDevicePropertyListenerBlock: AudioObjectPropertyListenerBlock =
    { [weak self] _, _ in
      self?.handleOutputDeviceChanged()
    }

  init(onTransportTypeChanged: @escaping (AudioDeviceTransportType) -> Void) throws {
    self.onTransportTypeChanged = onTransportTypeChanged

    var defaultSystemOutputDevicePropertyAddress = defaultSystemOutputDevicePropertyAddress

    let status = AudioObjectAddPropertyListenerBlock(
      systemObjectID,
      &defaultSystemOutputDevicePropertyAddress,
      .main,
      defaultSystemOutputDevicePropertyListenerBlock
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
      defaultSystemOutputDevicePropertyListenerBlock
    )
  }

  func currentDeviceTransportType() throws -> AudioDeviceTransportType {
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
    let transportType = (try? currentDeviceTransportType()) ?? kAudioDeviceTransportTypeUnknown
    onTransportTypeChanged(transportType)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var outputDeviceObserver: OutputDeviceObserver?
  private var clickMonitor: ClickMonitor?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let outputDeviceObserver = try OutputDeviceObserver { [weak self] transportType in
        self?.clickMonitor?.setSuspended(transportType.isBluetooth)
      }

      let soundEffectManager = try SoundEffectManager()
      let currentOutputDeviceTransportType = try outputDeviceObserver.currentDeviceTransportType()
      let clickMonitor = try ClickMonitor(
        soundEffectManager: soundEffectManager,
        isSuspended: currentOutputDeviceTransportType.isBluetooth
      )

      self.outputDeviceObserver = outputDeviceObserver
      self.clickMonitor = clickMonitor
    } catch {
      FileHandle.standardError.write(Data("Failed to initialize: \(error.localizedDescription)\n".utf8))
      NSApplication.shared.terminate(nil)

      return
    }

    observeSignals()
    observeCommands()
  }

  private func observeSignals() {
    Task {
      for await _ in ProcessSignals.stream(for: [SIGHUP, SIGINT, SIGTERM]) {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func observeCommands() {
    Task {
      let notificationCenter = DistributedNotificationCenter.default()

      for await notification in notificationCenter.notifications(named: Constants.notificationName) {
        guard
          let userInfo = notification.userInfo,
          let arguments = userInfo[Constants.notificationUserInfoKey] as? [String]
        else {
          continue
        }

        handleCommand(with: arguments)
      }
    }
  }

  private func handleCommand(with arguments: [String]) {
    guard let command = arguments.first else {
      return
    }

    switch command {
    case "toggle": clickMonitor?.toggleEnabled()
    case "quit": NSApplication.shared.terminate(nil)
    default: return
    }
  }
}

do {
  try MainActor.assumeIsolated {
    let singleInstanceLock = try SingleInstanceLock()
    let delegate = AppDelegate(singleInstanceLock: singleInstanceLock)
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    application.run()
  }

} catch SingleInstanceLock.Error.instanceAlreadyRunning {
  let arguments = Array(CommandLine.arguments.dropFirst())

  guard !arguments.isEmpty else {
    print("Already running, specify \"toggle\" or \"quit\" as an argument.")
    exit(0)
  }

  Command(arguments: arguments).send()
  exit(0)

} catch {
  FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
