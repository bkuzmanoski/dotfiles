import AppKit

enum Constants {
  static let subsystem = "industries.britown.SwitchToSpace"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
}

enum ProcessSignals {
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

final class SingleInstanceLock {
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

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: UInt32, _ display: CFString?) -> Unmanaged<CFArray>?

enum IOHIDEventType: Int64 {
  case dockSwipe = 23
}

enum CGSGesturePhase: Int64 {
  case began = 1
  case ended = 4
}

enum CGGestureMotion: Int64 {
  case horizontal = 1
}

extension CGEventField {
  static let cgsEventType = CGEventField(rawValue: 55)!
  static let gestureHIDType = CGEventField(rawValue: 110)!
  static let gestureScrollY = CGEventField(rawValue: 119)!
  static let gestureSwipeMotion = CGEventField(rawValue: 123)!
  static let gestureSwipeProgress = CGEventField(rawValue: 124)!
  static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
  static let gestureSwipeVelocityY = CGEventField(rawValue: 130)!
  static let gesturePhase = CGEventField(rawValue: 132)!
  static let scrollGestureFlagBits = CGEventField(rawValue: 135)!
  static let gestureZoomDeltaX = CGEventField(rawValue: 139)!
}

extension CGEventType {
  static let gesture = CGEventType(rawValue: 29)!
  static let dockControl = CGEventType(rawValue: 30)!
}

extension NSScreen {
  var displayIdentifier: String? {
    guard
      let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
      let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(screenNumber.uint32Value))?.takeRetainedValue()
    else {
      return nil
    }

    return CFUUIDCreateString(nil, uuid) as String
  }

  func spacesInfo() -> (spaceCount: Int, currentIndex: Int)? {
    let connectionID = CGSMainConnectionID()

    guard
      connectionID != 0,
      let displayIdentifier = self.displayIdentifier,
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        connectionID,
        displayIdentifier as CFString
      )?.takeRetainedValue() as? [[String: Any]],
      let displayDict = managedDisplaySpaces.first(where: { $0["Display Identifier"] as? String == displayIdentifier }),
      let currentSpaceDict = displayDict["Current Space"] as? [String: Any],
      let currentSpaceID = (currentSpaceDict["id64"] as? NSNumber)?.uint64Value,
      currentSpaceID != 0,
      let spacesDict = displayDict["Spaces"] as? [[String: Any]],
      !spacesDict.isEmpty,
      let activeSpaceIndex = spacesDict.firstIndex(where: { ($0["id64"] as? NSNumber)?.uint64Value == currentSpaceID })
    else {
      return nil
    }

    return (spacesDict.count, activeSpaceIndex)
  }
}

final class SpaceSwitcher {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionDenied

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied: "Accessibility permission denied."
      }
    }
  }

  enum Direction {
    case left
    case right
  }

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }
  }

  func switchSpace(direction: Direction) {
    guard let spacesInfo = NSScreen.main?.spacesInfo(), spacesInfo.spaceCount > 0 else {
      return
    }

    let offset = direction == .right ? 1 : -1
    let targetIndex = (spacesInfo.currentIndex + offset + spacesInfo.spaceCount) % spacesInfo.spaceCount

    performSwitch(to: targetIndex, spacesInfo: spacesInfo)
  }

  func switchToSpace(index: Int) {
    guard let spacesInfo = NSScreen.main?.spacesInfo(), spacesInfo.spaceCount > 0 else {
      return
    }

    performSwitch(to: index, spacesInfo: spacesInfo)
  }

  private func performSwitch(to index: Int, spacesInfo: (spaceCount: Int, currentIndex: Int)) {
    let targetIndex = min(max(index, 0), spacesInfo.spaceCount - 1)

    guard spacesInfo.currentIndex != targetIndex else {
      return
    }

    let direction: Direction = spacesInfo.currentIndex < targetIndex ? .right : .left
    let steps = direction == .right ? (targetIndex - spacesInfo.currentIndex) : (spacesInfo.currentIndex - targetIndex)

    for _ in 0..<steps {
      if !postDockControlEvent(direction: direction) {
        return
      }
    }
  }

  @discardableResult
  private func postDockControlEvent(direction: Direction) -> Bool {
    guard
      postDockControlEvent(.began, direction: direction, progress: 0, velocityX: 0),
      postDockControlEvent(
        .ended,
        direction: direction,
        progress: direction == .right ? 2.0 : -2.0,
        velocityX: direction == .right ? 400.0 : -400.0
      )
    else {
      return false
    }

    return true
  }

  private func postDockControlEvent(
    _ phase: CGSGesturePhase,
    direction: Direction,
    progress: Double,
    velocityX: Double
  ) -> Bool {
    guard let dockControlEvent = CGEvent(source: nil), let gestureEvent = CGEvent(source: nil) else {
      return false
    }

    dockControlEvent.type = .dockControl
    dockControlEvent.setIntegerValueField(.cgsEventType, value: Int64(CGEventType.dockControl.rawValue))
    dockControlEvent.setIntegerValueField(.gestureHIDType, value: IOHIDEventType.dockSwipe.rawValue)
    dockControlEvent.setIntegerValueField(.gesturePhase, value: phase.rawValue)
    dockControlEvent.setIntegerValueField(.scrollGestureFlagBits, value: direction == .right ? 1 : 0)
    dockControlEvent.setIntegerValueField(.gestureSwipeMotion, value: CGGestureMotion.horizontal.rawValue)
    dockControlEvent.setDoubleValueField(.gestureScrollY, value: 0)
    dockControlEvent.setDoubleValueField(.gestureZoomDeltaX, value: Double(Float.leastNonzeroMagnitude))

    if phase == .ended {
      dockControlEvent.setDoubleValueField(.gestureSwipeProgress, value: progress)
      dockControlEvent.setDoubleValueField(.gestureSwipeVelocityX, value: velocityX)
      dockControlEvent.setDoubleValueField(.gestureSwipeVelocityY, value: 0)
    }

    gestureEvent.type = .gesture
    gestureEvent.setIntegerValueField(.cgsEventType, value: Int64(CGEventType.gesture.rawValue))

    dockControlEvent.post(tap: .cgSessionEventTap)
    gestureEvent.post(tap: .cgSessionEventTap)

    return true
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var spaceSwitcher: SpaceSwitcher?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.spaceSwitcher = try SpaceSwitcher()
    } catch {
      FileHandle.standardError.write(Data("Error starting SpaceSwitcher: \(error.localizedDescription)\n".utf8))
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
    guard let command = arguments.first?.lowercased() else {
      return
    }

    switch command {
    case "quit":
      await NSApplication.shared.terminate(nil)

    case "left":
      spaceSwitcher?.switchSpace(direction: .left)

    case "right":
      spaceSwitcher?.switchSpace(direction: .right)

    default:
      if let spaceNumber = Int(command), spaceNumber > 0 {
        spaceSwitcher?.switchToSpace(index: spaceNumber - 1)
      }
    }
  }
}

do {
  let singleInstanceLock = try SingleInstanceLock()
  let delegate = AppDelegate(singleInstanceLock: singleInstanceLock)
  let application = NSApplication.shared
  application.setActivationPolicy(.prohibited)
  application.delegate = delegate
  application.run()

} catch SingleInstanceLock.Error.instanceAlreadyRunning {
  let arguments = Array(CommandLine.arguments.dropFirst())

  guard !arguments.isEmpty else {
    print(
      "Already running, specify a space to switch to (e.g., \"left\", \"right\", or number) or \"quit\" as an argument."
    )
    exit(0)
  }

  Command(arguments: arguments).send()
  exit(0)

} catch {
  FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
