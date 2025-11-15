import AppKit

enum Constants {
  static let subsystem = "industries.britown.ScrollToZoom"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let hotkey = CGEventFlags.maskAlternate
  static let zoomSensitivity = 0.005
  static let reverseZoomDirection = true
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
    guard let namePointer = strsignal(signal) else {
      return "Unknown signal (\(signal))"
    }

    return String(cString: namePointer)
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

      continuation.onTermination = { @Sendable _ in
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
    case failedToAcquireLock(String)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: "Instance already running."
      case .failedToAcquireLock(let message): "Failed to acquire lock: \(message)"
      }
    }
  }

  private let lockFilePath = NSTemporaryDirectory().appending(Constants.lockFileName)
  private var lockFileDescriptor: CInt

  init() throws {
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)

    if fd == -1 {
      throw Error.failedToAcquireLock(String(cString: strerror(errno)))
    }

    if flock(fd, LOCK_EX | LOCK_NB) == -1 {
      close(fd)

      guard errno == EWOULDBLOCK else {
        throw Error.failedToAcquireLock("Failed to acquire lock: \(String(cString: strerror(errno)))")
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

extension CGEventField {
  static let gestureHIDType = CGEventField(rawValue: 110)!
  static let gestureZoomValue = CGEventField(rawValue: 113)!
  static let gesturePhase = CGEventField(rawValue: 132)!
}

extension CGEventType {
  static let gesture = CGEventType(rawValue: 29)!
}

@MainActor
class ScrollZoomController {
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

  private enum IOHIDEventType: UInt32 {
    case zoom = 8
  }

  private enum CGSGesturePhase: UInt8 {
    case began = 1
    case changed = 2
    case ended = 4
  }

  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var isZooming = false

  func start() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.flagsChanged.rawValue),
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

  func stop() {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)

      if let runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      }

      CFMachPortInvalidate(eventTap)
    }

    self.eventTap = nil
    self.runLoopSource = nil
  }

  nonisolated func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let isHotkeyDown = event.flags.contains(Constants.hotkey)

    if type == .flagsChanged, !isHotkeyDown {
      Task {
        await endZooming()
      }
    }

    if type == .scrollWheel {
      if isHotkeyDown {
        Task {
          await beginZooming()

          let scrollDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

          if scrollDelta != 0 {
            await handleScrollEvent(delta: scrollDelta)
          }
        }

        return nil
      } else {
        Task {
          await endZooming()
        }
      }
    }

    return Unmanaged.passUnretained(event)
  }

  private func beginZooming() async {
    if !isZooming {
      self.isZooming = true

      try? await Task.sleep(for: .milliseconds(10))

      postPinchGestureEvent(phase: .began, magnification: 0)
    }
  }

  private func endZooming() {
    if isZooming {
      postPinchGestureEvent(phase: .ended, magnification: 0)
      self.isZooming = false
    }
  }

  private func handleScrollEvent(delta: Double) {
    let directionMultiplier = Constants.reverseZoomDirection ? -1.0 : 1.0
    let magnification = delta * directionMultiplier * Constants.zoomSensitivity
    postPinchGestureEvent(phase: .changed, magnification: magnification)
  }

  private func postPinchGestureEvent(phase: CGSGesturePhase, magnification: Double) {
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

func eventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let refcon else {
    return Unmanaged.passUnretained(event)
  }

  let controller = Unmanaged<ScrollZoomController>.fromOpaque(refcon).takeUnretainedValue()
  return controller.handleEvent(proxy: proxy, type: type, event: event)
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private var singletonLock: SingletonLock
  private var scrollZoomController: ScrollZoomController!

  init(singletonLock: SingletonLock) {
    self.singletonLock = singletonLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    self.scrollZoomController = ScrollZoomController()

    do {
      try scrollZoomController.start()
    } catch {
      FileHandle.standardError.write(Data("Error starting ScrollZoomController: \(error.localizedDescription)\n".utf8))
      NSApplication.shared.terminate(nil)
    }

    observeSignals()
    observeCommands()
  }

  func applicationWillTerminate(_ notification: Notification) {
    scrollZoomController.stop()
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
