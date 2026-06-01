import AppKit
import AudioToolbox
import System

enum Configuration {
  static let subsystem = "industries.britown.MouseClickSoundEffects"
  static let soundFileDirectoryPath = "~/.dotfiles/utils/assets"
}

struct FileDescriptorOutputStream: TextOutputStream {
  static var standardError = FileDescriptorOutputStream(.standardError)
  static var standardOutput = FileDescriptorOutputStream(.standardOutput)

  let fileDescriptor: FileDescriptor
  var errorHandler: ((Error) -> Void)?

  init(_ fileDescriptor: FileDescriptor, errorHandler: ((Error) -> Void)? = nil) {
    self.fileDescriptor = fileDescriptor
    self.errorHandler = errorHandler
  }

  mutating func write(_ string: String) {
    do {
      try fileDescriptor.writeAll(string.utf8)
    } catch {
      errorHandler?(error)
    }
  }
}

final class SingleInstanceLock {
  enum Error: Swift.Error, CustomStringConvertible {
    case instanceAlreadyRunning
    case failedToAcquireLock(underlyingError: Errno)

    var description: String {
      switch self {
      case .instanceAlreadyRunning: "Another instance is already running."
      case .failedToAcquireLock(let underlyingError): "Failed to acquire lock: \(underlyingError)"
      }
    }
  }

  private var lockFileDescriptor: FileDescriptor

  init(subsystem: String) throws {
    do {
      self.lockFileDescriptor = try FileDescriptor.open(
        FilePath(FileManager.default.temporaryDirectory.appendingPathComponent("\(subsystem).lock").path),
        .readWrite,
        options: [.create, .exclusiveLock, .nonBlocking],
        permissions: [.ownerReadWrite, .groupRead, .otherRead]
      )

    } catch let errno as Errno where errno == .wouldBlock {
      throw Error.instanceAlreadyRunning

    } catch let errno as Errno {
      throw Error.failedToAcquireLock(underlyingError: errno)
    }
  }

  deinit {
    do {
      try lockFileDescriptor.close()
    } catch {
      print("Failed to close lock file descriptor: \(error)", to: &FileDescriptorOutputStream.standardError)
    }
  }
}

enum ProcessSignals {
  static func stream(for signals: CInt...) -> AsyncStream<CInt> {
    let (stream, continuation) = AsyncStream.makeStream(of: CInt.self)

    var sources: [any DispatchSourceSignal] = []
    sources.reserveCapacity(signals.count)

    for signal in signals {
      Darwin.signal(signal, SIG_IGN)

      let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)

      source.setEventHandler {
        continuation.yield(signal)
      }

      source.setCancelHandler {
        Darwin.signal(signal, SIG_DFL)
      }

      source.resume()
      sources.append(source)
    }

    continuation.onTermination = { [sources] _ in
      sources.forEach { source in
        source.cancel()
      }
    }

    return stream
  }
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
  enum Error: Swift.Error, CustomStringConvertible {
    case soundFileDirectoryNotFound(path: String)
    case invalidSoundFileDirectoryPath(String)
    case soundFileNotFound(soundEffect: SoundEffect, path: String)

    var description: String {
      switch self {
      case .soundFileDirectoryNotFound(let path): "Sound file directory not found at path: \(path)"
      case .invalidSoundFileDirectoryPath(let path): "Invalid sound file directory path (not a directory): \(path)"
      case .soundFileNotFound(let soundEffect, let path): "Sound file for '\(soundEffect)' not found at path: \(path)"
      }
    }
  }

  private let systemSoundIDs: [SoundEffect: SystemSoundID]

  init(soundFileDirectoryURL: URL) throws {
    guard FileManager.default.fileExists(atPath: soundFileDirectoryURL.path) else {
      throw Error.soundFileDirectoryNotFound(path: soundFileDirectoryURL.path)
    }

    guard soundFileDirectoryURL.hasDirectoryPath else {
      throw Error.invalidSoundFileDirectoryPath(soundFileDirectoryURL.path)
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
  enum Error: Swift.Error, CustomStringConvertible {
    case accessibilityPermissionNotGranted
    case failedToCreateEventTap
    case failedToCreateRunLoopSource

    var description: String {
      switch self {
      case .accessibilityPermissionNotGranted: "Accessibility permission not granted."
      case .failedToCreateEventTap: "Failed to create event tap."
      case .failedToCreateRunLoopSource: "Failed to create run loop source for event tap."
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
          if let refcon, event.getIntegerValueField(.mouseEventSubtype) == NSEvent.EventSubtype.touch.rawValue {
            Unmanaged<ClickMonitor>.fromOpaque(refcon).takeUnretainedValue().handleEvent(ofType: type)
          }

          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
      CFMachPortInvalidate(eventTap)
      throw Error.failedToCreateRunLoopSource
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource

    updateEventTapState()
  }

  deinit {
    if let eventTap, let runLoopSource {
      if CGEvent.tapIsEnabled(tap: eventTap) {
        CGEvent.tapEnable(tap: eventTap, enable: false)
      }

      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFMachPortInvalidate(eventTap)
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

final class SystemOutputDeviceObserver {
  enum Error: Swift.Error, CustomStringConvertible {
    case failedToDetermineOutputDevice(status: OSStatus)
    case failedToDetermineDeviceTransportType(deviceID: AudioObjectID, status: OSStatus)
    case failedToObserveOutputDeviceChanges(status: OSStatus)

    var description: String {
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
      print(error, to: &FileDescriptorOutputStream.standardError)
      transportType = kAudioDeviceTransportTypeUnknown
    }

    onTransportTypeChanged(transportType)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var systemOutputDeviceObserver: SystemOutputDeviceObserver?
  private var clickMonitor: ClickMonitor?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let systemOutputDeviceObserver = try SystemOutputDeviceObserver { [weak self] transportType in
        self?.clickMonitor?.setSuspended(transportType.isBluetooth)
      }

      let soundEffectManager = try SoundEffectManager(
        soundFileDirectoryURL: URL(fileURLWithPath: Configuration.soundFileDirectoryPath, isDirectory: true)
      )
      let clickMonitor = try ClickMonitor(
        soundEffectManager: soundEffectManager,
        isSuspended: systemOutputDeviceObserver.currentTransportType().isBluetooth
      )

      self.systemOutputDeviceObserver = systemOutputDeviceObserver
      self.clickMonitor = clickMonitor
    } catch {
      print(error, to: &FileDescriptorOutputStream.standardError)
      exit(EXIT_FAILURE)
    }

    observeProcessSignals()
    observeIPCCommands()
  }

  private func observeProcessSignals() {
    Task {
      for await _ in ProcessSignals.stream(for: SIGINT, SIGTERM, SIGHUP) {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func observeIPCCommands() {
    Task {
      for await notification
        in DistributedNotificationCenter
        .default()
        .notifications(named: IPCCommand.notificationName)
      {
        guard
          let userInfo = notification.userInfo,
          let ipcCommandRawValue = userInfo[IPCCommand.notificationUserInfoKey] as? String,
          let ipcCommand = IPCCommand(rawValue: ipcCommandRawValue.lowercased())
        else {
          continue
        }

        handleIPCCommand(ipcCommand)
      }
    }
  }

  private func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .toggle: clickMonitor?.toggleEnabled()
    case .printLog: break
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, CaseIterable {
  case toggle
  case printLog = "print-log"
  case quit

  static let notificationName = Notification.Name("\(Configuration.subsystem).IPCCommand")
  static let notificationUserInfoKey = "command"

  func send() {
    DistributedNotificationCenter.default().postNotificationName(
      Self.notificationName,
      object: nil,
      userInfo: [Self.notificationUserInfoKey: self.rawValue],
      deliverImmediately: true
    )
  }
}

do {
  try MainActor.assumeIsolated {
    let singleInstanceLock = try SingleInstanceLock(subsystem: Configuration.subsystem)

    if isatty(STDOUT_FILENO) == 0 {
      do {
        let fd = try FileDescriptor.open(
          FilePath(
            FileManager.default.temporaryDirectory.appendingPathComponent("\(Configuration.subsystem).log").path
          ),
          .writeOnly,
          options: [.create, .truncate],
          permissions: [.ownerReadWrite, .groupRead, .otherRead]
        )

        try fd.closeAfter {
          _ = try fd.duplicate(as: .standardOutput)
          _ = try fd.duplicate(as: .standardError)
        }

        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
      } catch {
        print("Failed to redirect output: \(error)", to: &FileDescriptorOutputStream.standardError)
      }
    }

    let delegate = AppDelegate(singleInstanceLock: singleInstanceLock)
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    application.run()
  }

} catch SingleInstanceLock.Error.instanceAlreadyRunning {
  let arguments = CommandLine.arguments.dropFirst()

  lazy var usageDescription =
    "Usage: \(ProcessInfo.processInfo.processName) [\(IPCCommand.allCases.map(\.rawValue).joined(separator: "|"))]"

  guard let argument = arguments.first else {
    print("Already running.\n\n\(usageDescription)", to: &FileDescriptorOutputStream.standardError)
    exit(EX_USAGE)
  }

  guard arguments.dropFirst().isEmpty else {
    print("Too many arguments.\n\n\(usageDescription)", to: &FileDescriptorOutputStream.standardError)
    exit(EX_USAGE)
  }

  guard let ipcCommand = IPCCommand(rawValue: argument.lowercased()) else {
    print("Unknown command.\n\n\(usageDescription)", to: &FileDescriptorOutputStream.standardError)
    exit(EX_USAGE)
  }

  if case .printLog = ipcCommand {
    let logFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(Configuration.subsystem).log")

    guard FileManager.default.fileExists(atPath: logFileURL.path) else {
      print("Log file does not exist.", to: &FileDescriptorOutputStream.standardError)
      exit(EX_NOINPUT)
    }

    print("Log file path: \(logFileURL.path)\n")

    do {
      let logContents = try String(contentsOf: logFileURL, encoding: .utf8)

      if logContents.isEmpty {
        print("<EMPTY>")
      } else {
        print(logContents)
      }
    } catch {
      print("Failed to read log file: \(error)", to: &FileDescriptorOutputStream.standardError)
      exit(EXIT_FAILURE)
    }
  } else {
    ipcCommand.send()
  }

  exit(EXIT_SUCCESS)

} catch {
  print(error, to: &FileDescriptorOutputStream.standardError)
  exit(EXIT_FAILURE)
}
