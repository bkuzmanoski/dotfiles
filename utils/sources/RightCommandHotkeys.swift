import AppKit

enum Configuration {
  static let subsystem = "industries.britown.RightCommandHotkeys"
  static let keymap = [
    CGKeyCode.l: CGKeyCode.leftArrow,
    CGKeyCode.quote: CGKeyCode.rightArrow,
    CGKeyCode.p: CGKeyCode.upArrow,
    CGKeyCode.semicolon: CGKeyCode.downArrow,
    CGKeyCode.returnKey: CGKeyCode.returnKey
  ]
}

extension CGKeyCode {
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

extension CGEventFlags {
  static let maskLeftCommand = CGEventFlags(rawValue: 0x08)
  static let maskRightCommand = CGEventFlags(rawValue: 0x10)
}

@MainActor
final class HotkeyManager {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionNotGranted
    case failedToCreateEventTap

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionNotGranted: "Accessibility permission not granted."
      case .failedToCreateEventTap: "Failed to create event tap."
      }
    }
  }

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var activeHotkeys: [CGKeyCode: CGKeyCode] = [:]

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: 1 << CGEventType.keyDown.rawValue | 1 << CGEventType.keyUp.rawValue,
        callback: { _, _, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }

          return Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue().handleKeyboardEvent(event)
            ? nil
            : Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
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

  private func handleKeyboardEvent(_ event: CGEvent) -> Bool {
    guard event.type != .tapDisabledByTimeout, event.type != .tapDisabledByUserInput else {
      if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }

      return false
    }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let isKeyDown = event.type == .keyDown

    let mappedKeyCode: CGKeyCode

    if !isKeyDown, let activeHotkey = activeHotkeys[keyCode] {
      activeHotkeys[keyCode] = nil
      mappedKeyCode = activeHotkey

    } else if isKeyDown, event.flags.contains(.maskRightCommand), let mappedCode = Configuration.keymap[keyCode] {
      activeHotkeys[keyCode] = mappedCode
      mappedKeyCode = mappedCode

    } else {
      return false
    }

    guard let mappedEvent = CGEvent(keyboardEventSource: nil, virtualKey: mappedKeyCode, keyDown: isKeyDown) else {
      return false
    }

    var mappedFlags = event.flags

    mappedFlags.remove(.maskRightCommand)

    if !event.flags.contains(.maskLeftCommand) {
      mappedFlags.remove(.maskCommand)
    }

    mappedEvent.flags = mappedFlags
    mappedEvent.post(tap: .cghidEventTap)

    return true
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var hotkeyManager: HotkeyManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.hotkeyManager = try HotkeyManager()
    } catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(EXIT_FAILURE)
    }

    observeProcessSignals()
    observeAppCommands()
  }

  private func observeProcessSignals() {
    Task {
      for await _ in ProcessSignals.stream(for: SIGINT, SIGTERM, SIGHUP) {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func observeAppCommands() {
    Task {
      let notificationCenter = DistributedNotificationCenter.default()

      for await notification in notificationCenter.notifications(named: AppCommand.notificationName) {
        guard
          let userInfo = notification.userInfo,
          let appCommandRawValue = userInfo[AppCommand.notificationUserInfoKey] as? String,
          let appCommand = AppCommand(rawValue: appCommandRawValue.lowercased())
        else {
          continue
        }

        handleAppCommand(appCommand)
      }
    }
  }

  private func handleAppCommand(_ appCommand: AppCommand) {
    switch appCommand {
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

final class SingleInstanceLock {
  enum Error: Swift.Error, LocalizedError {
    case instanceAlreadyRunning
    case failedToAcquireLock(errno: Int32)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: "Instance already running."
      case .failedToAcquireLock(let errno): "Failed to acquire lock (\(String(cString: strerror(errno))))."
      }
    }
  }

  private let lockFilePath = FileManager.default.temporaryDirectory.appendingPathComponent(
    "\(Configuration.subsystem).lock"
  ).path
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

enum AppCommand: String, CaseIterable {
  case quit

  static let notificationName = Notification.Name("\(Configuration.subsystem).Command")
  static let notificationUserInfoKey = "command"

  static var usageDescription: String {
    "Usage: \(CommandLine.arguments.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "command") [\(Self.allCases.map(\.rawValue).joined(separator: "|"))]"
  }

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
    let singleInstanceLock = try SingleInstanceLock()
    let delegate = AppDelegate(singleInstanceLock: singleInstanceLock)
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    application.run()
  }

} catch SingleInstanceLock.Error.instanceAlreadyRunning {
  let arguments = CommandLine.arguments.dropFirst()

  guard let argument = arguments.first else {
    FileHandle.standardError.write(Data("Already running.\n\n\(AppCommand.usageDescription)\n".utf8))
    exit(EX_USAGE)
  }

  guard arguments.dropFirst().isEmpty else {
    FileHandle.standardError.write(Data("Too many arguments.\n\n\(AppCommand.usageDescription)\n".utf8))
    exit(EX_USAGE)
  }

  guard let appCommand = AppCommand(rawValue: argument.lowercased()) else {
    FileHandle.standardError.write(Data("Unknown command.\n\n\(AppCommand.usageDescription)\n".utf8))
    exit(EX_USAGE)
  }

  appCommand.send()

  exit(EXIT_SUCCESS)

} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(EXIT_FAILURE)
}
