import AppKit
import CoreGraphics

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
      case .interrupted(let signal): return "Interrupted with signal \(Signal.name(for: signal))"
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
    case lockFileError(String)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: return "Instance already running."
      case .lockFileError(let message): return "Failed to acquire lock: \(message)"
      }
    }
  }

  private let lockFilePath = NSTemporaryDirectory().appending(Constants.lockFileName)
  private var lockFileDescriptor: CInt

  init() throws {
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)

    if fd == -1 {
      throw Error.lockFileError(String(cString: strerror(errno)))
    }

    if flock(fd, LOCK_EX | LOCK_NB) == -1 {
      close(fd)

      guard errno == EWOULDBLOCK else {
        throw Error.lockFileError("Failed to acquire lock: \(String(cString: strerror(errno)))")
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
    case eventTapCreationFailed

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied: return "Accessibility permission denied."
      case .eventTapCreationFailed: return "Failed to create event tap."
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
  private var scrollZoomBegan = false

  func start() throws {
    guard checkPermissions() else {
      throw Error.accessibilityPermissionDenied
    }

    let eventMask = (1 << CGEventType.scrollWheel.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
    let selfPointer = Unmanaged.passUnretained(self).toOpaque()

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: eventTapCallback,
        userInfo: selfPointer
      )
    else {
      throw Error.eventTapCreationFailed
    }

    self.eventTap = tap
    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

    CFRunLoopAddSource(CFRunLoopGetMain(), self.runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  func stop() {
    if let tap = self.eventTap {
      CGEvent.tapEnable(tap: tap, enable: false)

      if let source = self.runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
      }
    }

    self.eventTap = nil
    self.runLoopSource = nil
  }

  private func checkPermissions() -> Bool {
    return AXIsProcessTrustedWithOptions(nil)
  }

  private func postPinchGestureEvent(phase: CGSGesturePhase, magnification: Double) {
    guard let event = CGEvent(source: nil) else { return }
    event.type = .gesture
    event.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.zoom.rawValue))
    event.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
    event.setDoubleValueField(.gestureZoomValue, value: magnification)
    event.post(tap: .cghidEventTap)
  }

  private func startZoom() async {
    if !scrollZoomBegan {
      scrollZoomBegan = true

      try? await Task.sleep(for: .milliseconds(10))

      postPinchGestureEvent(phase: .began, magnification: 0)
    }
  }

  private func endZoom() {
    if scrollZoomBegan {
      postPinchGestureEvent(phase: .ended, magnification: 0)
      scrollZoomBegan = false
    }
  }

  private func handleScroll(delta: Double) {
    let directionMultiplier = Constants.reverseZoomDirection ? -1.0 : 1.0
    let magnification = delta * directionMultiplier * Constants.zoomSensitivity
    postPinchGestureEvent(phase: .changed, magnification: magnification)
  }

  nonisolated func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let isHotkeyDown = event.flags.contains(Constants.hotkey)

    if type == .flagsChanged, !isHotkeyDown {
      Task { await self.endZoom() }
    }

    if type == .scrollWheel {
      if isHotkeyDown {
        Task {
          await self.startZoom()

          let scrollDelta = event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1)

          if scrollDelta != 0 {
            await self.handleScroll(delta: scrollDelta)
          }
        }

        return nil
      } else {
        Task {
          await self.endZoom()
        }
      }
    }

    return Unmanaged.passUnretained(event)
  }
}

private func eventTapCallback(
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
    scrollZoomController = ScrollZoomController()

    do {
      try scrollZoomController.start()
    } catch {
      print("Error starting ScrollZoomController: \(error.localizedDescription)")
      NSApplication.shared.terminate(nil)
    }

    Task {
      let stream = DistributedNotificationCenter.default().notifications(named: Constants.notificationName)

      for await notification in stream {
        guard
          let userInfo = notification.userInfo,
          let arguments = userInfo[Constants.notificationUserInfoKey] as? [String]
        else {
          continue
        }

        await handleCommand(with: arguments)
      }
    }

    Task {
      for await signal in Signal.stream(for: [SIGHUP, SIGINT, SIGTERM]) {
        print("Received \(Signal.name(for: signal)), shutting down.")
        await terminateApp()
      }
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    scrollZoomController.stop()
  }

  private func handleCommand(with arguments: [String]) async {
    guard let command = arguments.first else {
      return
    }

    switch command {
    case "quit": await terminateApp()
    default: return
    }
  }

  private func terminateApp() async {
    await NSApplication.shared.terminate(nil)
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
  print("An unhandled error occurred: \(error.localizedDescription)")
  exit(1)
}
