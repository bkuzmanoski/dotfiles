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

          return
            Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue().handleKeyboardEvent(event)
            ? nil
            : Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      ),
      let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    else {
      throw Error.failedToCreateEventTap
    }

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
      let notificationCenter = DistributedNotificationCenter.default()

      for await notification in notificationCenter.notifications(named: IPCCommand.notificationName) {
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
      case .instanceAlreadyRunning: "Another instance is already running."
      case .failedToAcquireLock(let errno): "Failed to acquire lock (\(String(cString: strerror(errno))))."
      }
    }
  }

  private let lockFilePath = FileManager.default.temporaryDirectory.appendingPathComponent(
    "\(Configuration.subsystem).lock"
  ).path
  private var lockFileDescriptor: CInt

  init() throws {
    let lockFileDescriptor = open(lockFilePath, O_CREAT | O_RDWR, 0o644)

    guard lockFileDescriptor != -1 else {
      throw Error.failedToAcquireLock(errno: errno)
    }

    guard flock(lockFileDescriptor, LOCK_EX | LOCK_NB) != -1 else {
      let flockErrno = errno

      close(lockFileDescriptor)

      guard flockErrno == EWOULDBLOCK else {
        throw Error.failedToAcquireLock(errno: flockErrno)
      }

      throw Error.instanceAlreadyRunning
    }

    self.lockFileDescriptor = lockFileDescriptor
  }

  deinit {
    flock(lockFileDescriptor, LOCK_UN)
    close(lockFileDescriptor)
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

enum IPCCommand: String, CaseIterable {
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
    let singleInstanceLock = try SingleInstanceLock()
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
    FileHandle.standardError.write(Data("Already running.\n\n\(usageDescription)\n".utf8))
    exit(EX_USAGE)
  }

  guard arguments.dropFirst().isEmpty else {
    FileHandle.standardError.write(Data("Too many arguments.\n\n\(usageDescription)\n".utf8))
    exit(EX_USAGE)
  }

  guard let ipcCommand = IPCCommand(rawValue: argument.lowercased()) else {
    FileHandle.standardError.write(Data("Unknown command.\n\n\(usageDescription)\n".utf8))
    exit(EX_USAGE)
  }

  ipcCommand.send()

  exit(EXIT_SUCCESS)

} catch {
  FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
  exit(EXIT_FAILURE)
}
