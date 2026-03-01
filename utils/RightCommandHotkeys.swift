import AppKit

enum Constants {
  static let subsystem = "industries.britown.RightCommandHotkeys"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let rightCommandDeviceBit: UInt64 = 0x10
  static let leftCommandDeviceBit: UInt64 = 0x08
  static let keymap: [CGKeyCode: CGKeyCode] = [
    KeyCode.l: KeyCode.leftArrow,
    KeyCode.quote: KeyCode.rightArrow,
    KeyCode.p: KeyCode.upArrow,
    KeyCode.semicolon: KeyCode.downArrow,
    KeyCode.returnKey: KeyCode.returnKey
  ]
}

enum KeyCode {
  static let l: CGKeyCode = 37
  static let quote: CGKeyCode = 39
  static let p: CGKeyCode = 35
  static let semicolon: CGKeyCode = 41
  static let returnKey: CGKeyCode = 36
  static let leftArrow: CGKeyCode = 123
  static let rightArrow: CGKeyCode = 124
  static let upArrow: CGKeyCode = 126
  static let downArrow: CGKeyCode = 125
}

enum Signal {
  enum Error: Swift.Error, LocalizedError {
    case interrupted(CInt)

    var errorDescription: String? {
      switch self {
      case .interrupted(let signal): "Interrupted with signal \(Signal.name(for: signal))"
      }
    }
  }

  static func name(for signal: CInt) -> String {
    guard let signalName = strsignal(signal) else {
      return "Unknown signal (\(signal))"
    }

    return String(cString: signalName)
  }

  static func stream(for signals: [CInt]) -> AsyncStream<CInt> {
    return AsyncStream { continuation in
      let sources = signals.map { signal in
        DispatchSource.makeSignalSource(signal: signal, queue: .main)
      }

      for (signal, source) in zip(signals, sources) {
        source.setEventHandler { continuation.yield(signal) }
        source.resume()
      }

      continuation.onTermination = { _ in
        sources.forEach { $0.cancel() }
      }
    }
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

class SingletonLock {
  enum Error: Swift.Error, LocalizedError {
    case instanceAlreadyRunning
    case failedToAcquireLock(errno: Int32)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: "Instance already running."
      case .failedToAcquireLock(let errno): "Failed to acquire lock: \(String(cString: strerror(errno)))"
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

class HotkeyController {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionDenied
    case failedToCreateEventTap

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied: "Accessibility permission denied."
      case .failedToCreateEventTap: "Failed to create event tap."
      }
    }
  }

  private(set) var eventTap: CFMachPort?

  private var runLoopSource: CFRunLoopSource?
  private var activeHotkeys: [CGKeyCode: CGKeyCode] = [:]

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }

    let eventsOfInterest: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: eventsOfInterest,
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

  func handleKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let isKeyDown = type == .keyDown

    if !isKeyDown, let mappedCode = activeHotkeys[keyCode] {
      activeHotkeys[keyCode] = nil
      postKeyEvent(keyCode: mappedCode, isKeyDown: false, originalEvent: event)
      return nil
    }

    guard event.flags.rawValue & Constants.rightCommandDeviceBit != 0, let mappedCode = Constants.keymap[keyCode] else {
      return Unmanaged.passUnretained(event)
    }

    if isKeyDown {
      activeHotkeys[keyCode] = mappedCode
      postKeyEvent(keyCode: mappedCode, isKeyDown: true, originalEvent: event)
    }

    return nil
  }

  private func postKeyEvent(keyCode: CGKeyCode, isKeyDown: Bool, originalEvent: CGEvent) {
    guard let newEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: isKeyDown) else {
      return
    }

    var newFlags = originalEvent.flags.rawValue
    newFlags &= ~Constants.rightCommandDeviceBit

    if !(originalEvent.flags.rawValue & Constants.leftCommandDeviceBit != 0) {
      newFlags &= ~CGEventFlags.maskCommand.rawValue
    }

    newEvent.flags = CGEventFlags(rawValue: newFlags)
    newEvent.post(tap: .cghidEventTap)
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

  let controller = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()

  guard type != .tapDisabledByTimeout, type != .tapDisabledByUserInput else {
    if let eventTap = controller.eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    return Unmanaged.passUnretained(event)
  }

  return controller.handleKeyEvent(type: type, event: event)
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private let singletonLock: SingletonLock
  private var hotkeyController: HotkeyController?

  init(singletonLock: SingletonLock) {
    self.singletonLock = singletonLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.hotkeyController = try HotkeyController()
    } catch {
      FileHandle.standardError.write(Data("Error starting HotkeyController: \(error.localizedDescription)\n".utf8))
      NSApplication.shared.terminate(nil)

      return
    }

    observeSignals()
    observeCommands()
  }

  private func observeSignals() {
    Task {
      for await _ in Signal.stream(for: [SIGHUP, SIGINT, SIGTERM]) {
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
  let singletonLock = try SingletonLock()
  let delegate = AppDelegate(singletonLock: singletonLock)
  let application = NSApplication.shared
  application.delegate = delegate
  application.run()

} catch SingletonLock.Error.instanceAlreadyRunning {
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
