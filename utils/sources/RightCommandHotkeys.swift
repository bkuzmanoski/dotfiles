import AppKit
import Carbon.HIToolbox
import Synchronization
import System

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

enum Log {
  enum Error: Swift.Error, LocalizedError {
    case outputAlreadyRedirected

    var errorDescription: String? {
      switch self {
      case .outputAlreadyRedirected: "Output has already been redirected."
      }
    }
  }

  private static let timestampStyle =
    isatty(FileDescriptor.standardOutput.rawValue) == 0
    ? Date.ISO8601FormatStyle(
      dateTimeSeparator: .space,
      includingFractionalSeconds: true,
      timeZone: .current
    ) : nil
  private static let isRedirected = Atomic(false)

  static func redirectOutput(to filePath: FilePath) throws {
    let (exchanged, _) = isRedirected.compareExchange(
      expected: false,
      desired: true,
      ordering: .acquiringAndReleasing
    )

    guard exchanged else {
      throw Error.outputAlreadyRedirected
    }

    do {
      let fileDescriptor = try FileDescriptor.open(
        filePath,
        .writeOnly,
        options: [.create, .truncate, .append],
        permissions: [.ownerReadWrite, .groupRead, .otherRead]
      )

      try fileDescriptor.closeAfter {
        _ = try fileDescriptor.duplicate(as: .standardOutput)
        _ = try fileDescriptor.duplicate(as: .standardError)
      }

      setvbuf(stdout, nil, _IONBF, 0)
      setvbuf(stderr, nil, _IONBF, 0)
    } catch {
      isRedirected.store(false, ordering: .releasing)
      throw error
    }
  }

  static func message(_ message: String) {
    write(message, to: .standardOutput)
  }

  static func error(_ message: String) {
    write(message, to: .standardError)
  }

  private static func write(_ message: String, to fileDescriptor: FileDescriptor) {
    _ = try? fileDescriptor.writeAll(line(for: message).utf8)
  }

  private static func line(for message: String) -> String {
    guard let timestampStyle else {
      return "\(message)\n"
    }

    return "[\(Date.now.formatted(timestampStyle))] \(message)\n"
  }
}

final class SingleInstanceLock {
  enum Error: Swift.Error, LocalizedError {
    case instanceAlreadyRunning
    case failedToAcquireLock(underlyingError: Errno)

    var errorDescription: String? {
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
      Log.error("Failed to close lock file descriptor: \(error.localizedDescription)")
    }
  }
}

enum ProcessSignals {
  static func stream(for signals: Int32...) -> AsyncStream<Int32> {
    let (stream, continuation) = AsyncStream.makeStream(of: Int32.self)

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

extension CGEventFlags {
  static let maskLeftCommand = CGEventFlags(rawValue: 0x08)
  static let maskRightCommand = CGEventFlags(rawValue: 0x10)
}

@MainActor
final class HotkeyManager {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionNotGranted
    case failedToCreateEventTap
    case failedToCreateRunLoopSource

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionNotGranted: "Accessibility permission not granted."
      case .failedToCreateEventTap: "Failed to create event tap."
      case .failedToCreateRunLoopSource: "Failed to create run loop source for event tap."
      }
    }
  }

  private let startDate = Date.now
  private let keymap: [CGKeyCode: CGKeyCode]
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var activeHotkeys: [CGKeyCode: CGKeyCode] = [:]

  init(keymap: [CGKeyCode: CGKeyCode]) throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    self.keymap = keymap

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(
          [
            CGEventType.keyDown,
            CGEventType.keyUp
          ].reduce(0) { $0 | (1 << $1.rawValue) }
        ),
        callback: { _, _, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }

          return MainActor.assumeIsolated {
            Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue().handleEvent(event)
          }
            ? nil
            : Unmanaged.passUnretained(event)
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
    CGEvent.tapEnable(tap: eventTap, enable: true)

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
  }

  isolated deinit {
    if let eventTap, let runLoopSource {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFMachPortInvalidate(eventTap)
    }
  }

  func logDiagnosticReport() {
    Log.message(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Event tap enabled: \(eventTap.map { "\(CGEvent.tapIsEnabled(tap: $0))" } ?? "<none>")
        Mapped hotkeys: \(keymap.count)
        Active hotkeys: \(activeHotkeys.count)
      """
    )
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    guard event.type != .tapDisabledByTimeout, event.type != .tapDisabledByUserInput else {
      if let eventTap {
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

    } else if isKeyDown, event.flags.contains(.maskRightCommand), let mappedCode = keymap[keyCode] {
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
  private var singleInstanceLock: SingleInstanceLock?
  private var hotkeyManager: HotkeyManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.hotkeyManager = try HotkeyManager(keymap: Configuration.keymap)
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }

    observeProcessSignals()
    observeIPCCommands()
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.singleInstanceLock = nil
    self.hotkeyManager = nil
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
    case .printLog: hotkeyManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, CaseIterable {
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

    if isatty(FileDescriptor.standardOutput.rawValue) == 0 {
      do {
        try Log.redirectOutput(
          to: FilePath(
            FileManager.default.temporaryDirectory.appendingPathComponent("\(Configuration.subsystem).log").path
          )
        )
      } catch {
        Log.error("Failed to redirect output: \(error.localizedDescription)")
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
    Log.error("Already running.\n\n\(usageDescription)")
    exit(EX_USAGE)
  }

  guard arguments.dropFirst().isEmpty else {
    Log.error("Too many arguments.\n\n\(usageDescription)")
    exit(EX_USAGE)
  }

  guard let ipcCommand = IPCCommand(rawValue: argument.lowercased()) else {
    Log.error("Unknown command.\n\n\(usageDescription)")
    exit(EX_USAGE)
  }

  ipcCommand.send()

  if case .printLog = ipcCommand {
    Thread.sleep(forTimeInterval: 0.2)

    let logFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(Configuration.subsystem).log")

    guard FileManager.default.fileExists(atPath: logFileURL.path) else {
      Log.error("Log file does not exist.")
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
      Log.error("Failed to read log file: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }

  exit(EXIT_SUCCESS)

} catch {
  Log.error(error.localizedDescription)
  exit(EXIT_FAILURE)
}
