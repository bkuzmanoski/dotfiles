import AppKit
import AudioToolbox

enum Constants {
  static let subsystem = "industries.britown.ClickSoundEffects"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let soundsDirectory = "~/.dotfiles/utils/assets"
  static let leftMouseDownSoundFile = "left-click-down.wav"
  static let leftMouseUpSoundFile = "left-click-up.wav"
  static let rightMouseDownSoundFile = "right-click-down.wav"
  static let rightMouseUpSoundFile = "right-click-up.wav"
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

final class SoundManager {
  enum Error: Swift.Error, LocalizedError {
    case soundFileNotFound(path: String)

    var errorDescription: String? {
      switch self {
      case .soundFileNotFound(let path): return "Sound file not found: \(path)"
      }
    }
  }

  private let leftMouseDownSound: SystemSoundID
  private let leftMouseUpSound: SystemSoundID
  private let rightMouseDownSound: SystemSoundID
  private let rightMouseUpSound: SystemSoundID

  init() throws {
    let soundsDirectoryPath = NSString(string: Constants.soundsDirectory).expandingTildeInPath
    let soundsDirectoryURL = URL(fileURLWithPath: soundsDirectoryPath, isDirectory: true)

    self.leftMouseDownSound = try Self.loadSound(
      at: soundsDirectoryURL.appendingPathComponent(Constants.leftMouseDownSoundFile)
    )
    self.leftMouseUpSound = try Self.loadSound(
      at: soundsDirectoryURL.appendingPathComponent(Constants.leftMouseUpSoundFile)
    )
    self.rightMouseDownSound = try Self.loadSound(
      at: soundsDirectoryURL.appendingPathComponent(Constants.rightMouseDownSoundFile)
    )
    self.rightMouseUpSound = try Self.loadSound(
      at: soundsDirectoryURL.appendingPathComponent(Constants.rightMouseUpSoundFile)
    )
  }

  deinit {
    AudioServicesDisposeSystemSoundID(leftMouseDownSound)
    AudioServicesDisposeSystemSoundID(leftMouseUpSound)
    AudioServicesDisposeSystemSoundID(rightMouseDownSound)
    AudioServicesDisposeSystemSoundID(rightMouseUpSound)
  }

  private static func loadSound(at url: URL) throws -> SystemSoundID {
    var soundID: SystemSoundID = 0

    guard FileManager.default.fileExists(atPath: url.path) else {
      throw Error.soundFileNotFound(path: url.path)
    }

    AudioServicesCreateSystemSoundID(url as CFURL, &soundID)

    return soundID
  }

  func playLeftDown() {
    play(soundID: leftMouseDownSound)
  }

  func playLeftUp() {
    play(soundID: leftMouseUpSound)
  }

  func playRightDown() {
    play(soundID: rightMouseDownSound)
  }

  func playRightUp() {
    play(soundID: rightMouseUpSound)
  }

  private func play(soundID: SystemSoundID) {
    guard soundID != 0 else {
      return
    }

    AudioServicesPlaySystemSound(soundID)
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

  private var runLoopSource: CFRunLoopSource?
  private let soundManager: SoundManager

  init(soundManager: SoundManager) throws {
    self.soundManager = soundManager

    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: (1 << CGEventType.leftMouseDown.rawValue)
          | (1 << CGEventType.leftMouseUp.rawValue)
          | (1 << CGEventType.rightMouseDown.rawValue)
          | (1 << CGEventType.rightMouseUp.rawValue),
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
    case .leftMouseDown: soundManager.playLeftDown()
    case .leftMouseUp: soundManager.playLeftUp()
    case .rightMouseDown: soundManager.playRightDown()
    case .rightMouseUp: soundManager.playRightUp()
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
  private var soundManager: SoundManager?
  private var clickMonitor: ClickMonitor?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let soundManager = try SoundManager()
      let clickMonitor = try ClickMonitor(soundManager: soundManager)

      self.soundManager = soundManager
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
    print("Already running, specify \"quit\" to stop.")
    exit(0)
  }

  Command(arguments: arguments).send()
  exit(0)

} catch {
  FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
