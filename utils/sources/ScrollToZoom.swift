import AppKit
import System

enum Configuration {
  static let subsystem = "industries.britown.ScrollToZoom"
  static let modifierKey: CGEventFlags = .maskAlternate
  static let zoomSensitivity = 0.005
}

struct FileDescriptorOutputStream: TextOutputStream {
  static var standardOutput = FileDescriptorOutputStream(.standardOutput)
  static var standardError = FileDescriptorOutputStream(.standardError)

  let fileDescriptor: FileDescriptor
  var errorHandler: ((any Error) -> Void)?

  init(_ fileDescriptor: FileDescriptor, errorHandler: ((any Error) -> Void)? = nil) {
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

enum IOHIDEventType: UInt32 {
  case zoom = 8
}

extension CGEvent {
  var scrollPhase: CGScrollPhase? {
    get {
      guard let scrollPhaseRawValue = UInt32(exactly: getIntegerValueField(.scrollWheelEventScrollPhase)) else {
        return nil
      }

      return CGScrollPhase(rawValue: scrollPhaseRawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(newValue.rawValue))
      }
    }
  }

  var scrollWheelEventPointDeltaAxis1: Int64 {
    get { getIntegerValueField(.scrollWheelEventPointDeltaAxis1) }
    set { self.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: newValue) }
  }

  var gestureHIDType: IOHIDEventType? {
    get {
      guard let rawValue = UInt32(exactly: getIntegerValueField(.gestureHIDType)) else {
        return nil
      }

      return IOHIDEventType(rawValue: rawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.gestureHIDType, value: Int64(newValue.rawValue))
      }
    }
  }

  var gesturePhase: CGGesturePhase? {
    get {
      guard let rawValue = UInt32(exactly: getIntegerValueField(.gesturePhase)) else {
        return nil
      }

      return CGGesturePhase(rawValue: rawValue)
    }

    set {
      if let newValue {
        self.setIntegerValueField(.gesturePhase, value: Int64(newValue.rawValue))
      }
    }
  }

  var gestureZoomValue: Double {
    get { getDoubleValueField(.gestureZoomValue) }
    set { self.setDoubleValueField(.gestureZoomValue, value: newValue) }
  }
}

extension CGEventField {
  static let gestureHIDType = CGEventField(rawValue: 110)!
  static let gestureZoomValue = CGEventField(rawValue: 113)!
  static let gesturePhase = CGEventField(rawValue: 132)!
}

extension CGEventType {
  static let gesture = CGEventType(rawValue: 29)!
}

@MainActor
final class ZoomManager {
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

  private let modifierFlagsMask: CGEventFlags = [
    .maskShift,
    .maskControl,
    .maskAlternate,
    .maskCommand,
    .maskSecondaryFn
  ]
  private let modifierKey: CGEventFlags
  private let zoomSensitivity: Double
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var isZooming = false

  init(modifierKey: CGEventFlags, zoomSensitivity: Double) throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    self.modifierKey = modifierKey
    self.zoomSensitivity = zoomSensitivity

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
        callback: { _, _, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }

          return
            Unmanaged<ZoomManager>.fromOpaque(refcon).takeUnretainedValue().handleEvent(event)
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

  deinit {
    if let eventTap, let runLoopSource {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFMachPortInvalidate(eventTap)
    }
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    guard event.type == .scrollWheel else {
      return false
    }

    guard
      event.type != .tapDisabledByTimeout,
      event.type != .tapDisabledByUserInput,
      event.flags.intersection(modifierFlagsMask) == modifierKey
    else {
      if isZooming {
        self.isZooming = false

        postZoomGestureEvent(withPhase: .cancelled)

        if event.scrollPhase == .changed {
          event.scrollPhase = .began
        }
      }

      if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }

      return false
    }

    guard let scrollPhase = event.scrollPhase else {
      return false
    }

    switch scrollPhase {
    case .began where !isZooming:
      self.isZooming = true
      postZoomGestureEvent(withPhase: .began)

    case .changed:
      let wasZooming = isZooming

      if !isZooming {
        self.isZooming = true

        event.scrollPhase = .cancelled
        postZoomGestureEvent(withPhase: .began)
      }

      postZoomGestureEvent(
        withPhase: .changed,
        zoomValue: -(Double(event.scrollWheelEventPointDeltaAxis1) * zoomSensitivity)
      )

      return wasZooming

    case .cancelled where isZooming:
      self.isZooming = false
      postZoomGestureEvent(withPhase: .cancelled)

    case .ended where isZooming:
      self.isZooming = false
      postZoomGestureEvent(withPhase: .ended)

    default:
      break
    }

    return true
  }

  private func postZoomGestureEvent(withPhase phase: CGGesturePhase, zoomValue: Double = 0.0) {
    guard let event = CGEvent(source: nil) else {
      return
    }

    event.type = .gesture
    event.gestureHIDType = .zoom
    event.gesturePhase = phase
    event.gestureZoomValue = zoomValue
    event.post(tap: .cghidEventTap)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var zoomManager: ZoomManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.zoomManager = try ZoomManager(
        modifierKey: Configuration.modifierKey,
        zoomSensitivity: Configuration.zoomSensitivity
      )
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
    case .printLog: break
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

    print("Log file path: \(logFileURL.path)")

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
