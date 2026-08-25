import AppKit
import Carbon.HIToolbox
import Synchronization
import System

enum Configuration {
  static let subsystem = "industries.britown.LineDeleteGuard"
  static let exemptBundleIdentifiers: Set<String> = ["com.raycast.macos"]
  static let fallbackKeyRepeatInterval = 6
  static let fallbackKeyRepeatInitialDelay = 25
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

extension AXUIElement {
  enum Error: Swift.Error, LocalizedError {
    case typeMismatch

    var errorDescription: String? {
      switch self {
      case .typeMismatch: "Returned value type does not match expected type."
      }
    }
  }

  static func setGlobalMessagingTimeout(seconds timeoutInSeconds: Float) {
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeoutInSeconds)
  }

  static func focusedApplicationBundleIdentifier() throws -> String? {
    var rawValue: CFTypeRef?

    try AXUIElementCopyAttributeValue(
      AXUIElementCreateSystemWide(),
      kAXFocusedApplicationAttribute as CFString,
      &rawValue
    ).throwIfFailed()

    guard let rawValue, CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
      throw Error.typeMismatch
    }

    var processIdentifier: pid_t = -1

    try AXUIElementGetPid(rawValue as! AXUIElement, &processIdentifier).throwIfFailed()

    guard processIdentifier > 0 else {
      return nil
    }

    return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
  }
}

extension AXError: @retroactive _BridgedNSError, @retroactive Error, @retroactive LocalizedError {
  public var errorDescription: String? {
    let message: String

    switch self {
    case .success: message = "Success"
    case .failure: message = "Failure"
    case .illegalArgument: message = "Illegal argument"
    case .invalidUIElement: message = "Invalid UI element"
    case .invalidUIElementObserver: message = "Invalid UI element observer"
    case .cannotComplete: message = "Cannot complete"
    case .attributeUnsupported: message = "Attribute unsupported"
    case .actionUnsupported: message = "Action unsupported"
    case .notificationUnsupported: message = "Notification unsupported"
    case .notImplemented: message = "Not implemented"
    case .notificationAlreadyRegistered: message = "Notification already registered"
    case .notificationNotRegistered: message = "Notification not registered"
    case .apiDisabled: message = "API disabled"
    case .noValue: message = "No value"
    case .parameterizedAttributeUnsupported: message = "Parameterized attribute unsupported"
    case .notEnoughPrecision: message = "Not enough precision"
    @unknown default: message = "Unknown error"
    }

    return "AXError: \(message) (\(self.rawValue))"
  }
}

extension AXError {
  func throwIfFailed() throws {
    if self != .success {
      throw self
    }
  }
}

extension CGEventFlags {
  static let modifierFlagsMask: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand]
}

struct KeyRepeatSettings {
  private static let tick: Duration = .nanoseconds(1_000_000_000 / 60)

  let initialDelay: Duration
  let interval: Duration

  init(userDefaults: UserDefaults = .standard) {
    self.initialDelay =
      Self.tick
      * Self.ticks(
        forKey: "InitialKeyRepeat",
        fallback: Configuration.fallbackKeyRepeatInitialDelay,
        userDefaults: userDefaults
      )
    self.interval =
      Self.tick
      * Self.ticks(forKey: "KeyRepeat", fallback: Configuration.fallbackKeyRepeatInterval, userDefaults: userDefaults)
  }

  private static func ticks(forKey key: String, fallback: Int, userDefaults: UserDefaults = .standard) -> Int {
    guard let value = userDefaults.object(forKey: key) as? Int, value > 0 else {
      return fallback
    }

    return value
  }
}

@MainActor
final class LineDeleteManager {
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
  private let synthesizedEventMarker: Int64 = 0x4c44_4744
  private let exemptBundleIdentifiers: Set<String>
  private let keyRepeatSettings: KeyRepeatSettings
  private let eventSettlingDelay: Duration = .milliseconds(30)
  private let effectiveKeyRepeatInterval: Duration
  private let delayBeforeFirstRepeat: Duration
  private let delayBetweenRepeats: Duration
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var keyRepeatTask: Task<Void, Never>?

  private var isExemptApplicationFocused: Bool {
    do {
      guard
        let bundleIdentifier = try AXUIElement.focusedApplicationBundleIdentifier()
          ?? NSWorkspace.shared.frontmostApplication?.bundleIdentifier
      else {
        return false
      }

      return exemptBundleIdentifiers.contains(bundleIdentifier)
    } catch {
      Log.error("Failed to retrieve focused application bundle identifier: \(error.localizedDescription)")
      return false
    }
  }

  init(exemptBundleIdentifiers: Set<String>, keyRepeatSettings: KeyRepeatSettings) throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    self.exemptBundleIdentifiers = exemptBundleIdentifiers
    self.keyRepeatSettings = keyRepeatSettings
    self.effectiveKeyRepeatInterval = max(keyRepeatSettings.interval, eventSettlingDelay * 2)
    self.delayBeforeFirstRepeat = max(
      eventSettlingDelay,
      keyRepeatSettings.initialDelay - eventSettlingDelay
    )
    self.delayBetweenRepeats = effectiveKeyRepeatInterval - eventSettlingDelay

    AXUIElement.setGlobalMessagingTimeout(seconds: 0.05)

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
            Unmanaged<LineDeleteManager>.fromOpaque(refcon).takeUnretainedValue().handleEvent(event)
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
        Exempt applications: \(exemptBundleIdentifiers.sorted().joined(separator: ", "))
        Exempt application focused: \(isExemptApplicationFocused)
        Performing key sequences: \(keyRepeatTask != nil)
        Key repeat:
          Initial delay: \(keyRepeatSettings.initialDelay) (system)
          Interval: \(effectiveKeyRepeatInterval) (system: \(keyRepeatSettings.interval))
        Key sequence:
          Settling delay: \(eventSettlingDelay)
          Delay before first repeat: \(delayBeforeFirstRepeat)
          Delay between repeats: \(delayBetweenRepeats)
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

    guard
      event.getIntegerValueField(.eventSourceUserData) != synthesizedEventMarker,
      CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == CGKeyCode(kVK_Delete)
    else {
      return false
    }

    guard event.type == .keyDown else {
      guard keyRepeatTask != nil else {
        return false
      }

      stopPerformingKeySequences()

      return true
    }

    guard event.flags.intersection(.modifierFlagsMask) == .maskCommand else {
      stopPerformingKeySequences()
      return false
    }

    guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else {
      return keyRepeatTask != nil
    }

    guard isExemptApplicationFocused else {
      return false
    }

    startPerformingKeySequences()

    return true
  }

  private func startPerformingKeySequences() {
    keyRepeatTask?.cancel()
    self.keyRepeatTask = Task {
      guard await performKeySequence() else {
        return
      }

      do {
        try await Task.sleep(for: delayBeforeFirstRepeat)

        while !Task.isCancelled {
          guard await performKeySequence() else {
            return
          }

          try await Task.sleep(for: delayBetweenRepeats)
        }
      } catch {
        return
      }
    }
  }

  private func stopPerformingKeySequences() {
    keyRepeatTask?.cancel()
    keyRepeatTask = nil
  }

  private func performKeySequence() async -> Bool {
    guard postEvent(virtualKey: CGKeyCode(kVK_LeftArrow), flags: [.maskCommand, .maskShift]) else {
      Log.error("Failed to synthesize selection event.")
      return false
    }

    try? await Task.sleep(for: eventSettlingDelay)

    guard postEvent(virtualKey: CGKeyCode(kVK_Delete), flags: []) else {
      Log.error("Failed to synthesize delete event.")
      return false
    }

    return true
  }

  private func postEvent(virtualKey: CGKeyCode, flags: CGEventFlags) -> Bool {
    let events = [true, false].compactMap { isKeyDown in
      CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: isKeyDown)
    }

    guard events.count == 2 else {
      return false
    }

    for event in events {
      event.flags = flags
      event.setIntegerValueField(.eventSourceUserData, value: synthesizedEventMarker)
      event.post(tap: .cghidEventTap)
    }

    return true
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var singleInstanceLock: SingleInstanceLock?
  private var lineDeleteManager: LineDeleteManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.lineDeleteManager = try LineDeleteManager(
        exemptBundleIdentifiers: Configuration.exemptBundleIdentifiers,
        keyRepeatSettings: KeyRepeatSettings()
      )
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }

    observeProcessSignals()
    observeIPCCommands()
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.singleInstanceLock = nil
    self.lineDeleteManager = nil
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
    case .printLog: lineDeleteManager?.logDiagnosticReport()
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
