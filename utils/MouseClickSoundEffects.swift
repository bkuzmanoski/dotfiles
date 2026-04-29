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
      sources.forEach { $0.cancel() }
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

  private let lockFilePath = NSTemporaryDirectory().appending(Constants.lockFileName)
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
  private var isEnabled = true

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

  func toggleEnabled() {
    self.isEnabled.toggle()
  }

  func play(soundEffect: SoundEffect) {
    guard isEnabled, let soundID = systemSoundIDs[soundEffect] else {
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

final class ClickMonitor {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionDenied
    case failedToCreateEventTap

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied: return "Accessibility permission denied."
      case .failedToCreateEventTap: return "Failed to create event tap."
      }
    }
  }

  private(set) var eventTap: CFMachPort?

  private let soundEffectManager: SoundEffectManager
  private var runLoopSource: CFRunLoopSource?

  init(soundEffectManager: SoundEffectManager) throws {
    self.soundEffectManager = soundEffectManager

    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: 1 << CGEventType.leftMouseDown.rawValue
          | 1 << CGEventType.leftMouseUp.rawValue
          | 1 << CGEventType.rightMouseDown.rawValue
          | 1 << CGEventType.rightMouseUp.rawValue,
        callback: eventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    self.eventTap = eventTap
    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)
  }

  deinit {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
  }

  func handleEvent(type: CGEventType) {
    switch type {
    case .leftMouseDown: soundEffectManager.play(soundEffect: .leftMouseDown)
    case .leftMouseUp: soundEffectManager.play(soundEffect: .leftMouseUp)
    case .rightMouseDown: soundEffectManager.play(soundEffect: .rightMouseDown)
    case .rightMouseUp: soundEffectManager.play(soundEffect: .rightMouseUp)
    default: break
    }
  }
}

func eventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let refcon else {
    return Unmanaged.passUnretained(event)
  }

  let clickMonitor = Unmanaged<ClickMonitor>.fromOpaque(refcon).takeUnretainedValue()

  guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
    if let eventTap = clickMonitor.eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    return Unmanaged.passUnretained(event)
  }

  clickMonitor.handleEvent(type: type)

  return Unmanaged.passUnretained(event)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var soundEffectManager: SoundEffectManager?
  private var clickMonitor: ClickMonitor?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let soundEffectManager = try SoundEffectManager()
      let clickMonitor = try ClickMonitor(soundEffectManager: soundEffectManager)

      self.soundEffectManager = soundEffectManager
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
        await NSApplication.shared.terminate(nil)
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

        await handleCommand(with: arguments)
      }
    }
  }

  private func handleCommand(with arguments: [String]) async {
    guard let command = arguments.first else {
      return
    }

    switch command {
    case "toggle": soundEffectManager?.toggleEnabled()
    case "quit": await NSApplication.shared.terminate(nil)
    default: return
    }
  }
}

do {
  let singleInstanceLock = try SingleInstanceLock()
  let delegate = AppDelegate(singleInstanceLock: singleInstanceLock)
  let application = NSApplication.shared
  application.delegate = delegate
  application.setActivationPolicy(.prohibited)
  application.run()

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
