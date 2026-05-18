import AppKit

enum Configuration {
  static let subsystem = "industries.britown.ScrollToZoom"
  static let hotkey = CGEventFlags.maskAlternate
  static let zoomSensitivity = 0.005
  static let reverseZoomDirection = true
}

enum IOHIDEventType: UInt32 {
  case zoom = 8
}

enum CGSGesturePhase: UInt8 {
  case began = 1
  case changed = 2
  case ended = 4
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
  private var isZooming = false

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: 1 << CGEventType.scrollWheel.rawValue | 1 << CGEventType.flagsChanged.rawValue,
        callback: { _, _, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }

          return Unmanaged<ZoomManager>.fromOpaque(refcon).takeUnretainedValue().handleEvent(event)
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

  private func handleEvent(_ event: CGEvent) -> Bool {
    guard event.type != .tapDisabledByTimeout, event.type != .tapDisabledByUserInput else {
      if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }

      return false
    }

    guard event.type == .scrollWheel, event.flags.contains(Configuration.hotkey) else {
      guard isZooming else {
        return false
      }

      performZoomGesture(phase: .ended, magnification: 0.0)

      self.isZooming = false

      return true
    }

    if !isZooming {
      self.isZooming = true
      performZoomGesture(phase: .began, magnification: 0.0)
    }

    let scrollDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

    if scrollDelta != 0.0 {
      let directionMultiplier = Configuration.reverseZoomDirection ? -1.0 : 1.0
      let magnification = scrollDelta * directionMultiplier * Configuration.zoomSensitivity

      performZoomGesture(phase: .changed, magnification: magnification)
    }

    return true
  }

  private func performZoomGesture(phase: CGSGesturePhase, magnification: Double) {
    guard let event = CGEvent(source: nil) else {
      return
    }

    event.type = .gesture
    event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.zoom.rawValue))
    event.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
    event.setDoubleValueField(.gestureZoomValue, value: magnification)
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
      self.zoomManager = try ZoomManager()
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
