import AppKit

enum Configuration {
  static let subsystem = "industries.britown.SwitchToSpace"
}

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connectionID: CGSConnectionID, _ displayIdentifier: CFString?) -> Unmanaged<CFArray>?

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

typealias DisplayIdentifier = String
typealias SpaceID = UInt64

extension NSScreen {
  private var displayIdentifier: DisplayIdentifier? {
    guard
      let cgDirectDisplayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(cgDirectDisplayID)?.takeRetainedValue()
    else {
      return nil
    }

    return CFUUIDCreateString(nil, uuid) as DisplayIdentifier
  }

  func spacesInfo() -> (spaceCount: Int, currentIndex: Int)? {
    guard
      let displayIdentifier = self.displayIdentifier,
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        CGSMainConnectionID(),
        displayIdentifier as CFString
      )?.takeRetainedValue() as? [[String: Any]],
      let displayInfo = managedDisplaySpaces.first(where: {
        $0["Display Identifier"] as? DisplayIdentifier == displayIdentifier
      }),
      let spacesInfo = displayInfo["Spaces"] as? [[String: Any]],
      !spacesInfo.isEmpty,
      let currentSpaceInfo = displayInfo["Current Space"] as? [String: Any],
      let currentSpaceID = currentSpaceInfo["id64"] as? SpaceID,
      let currentSpaceIndex = spacesInfo.firstIndex(where: { $0["id64"] as? SpaceID == currentSpaceID })
    else {
      return nil
    }

    return (spacesInfo.count, currentSpaceIndex)
  }
}

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

final class SpaceSwitcher {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionNotGranted

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionNotGranted: "Accessibility permission not granted."
      }
    }
  }

  enum Direction {
    case left
    case right
  }

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
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
      if !performSpaceSwitchGesture(direction: direction) {
        return
      }
    }
  }

  @discardableResult
  private func performSpaceSwitchGesture(direction: Direction) -> Bool {
    guard
      performSpaceSwitchGesture(phase: .began, direction: direction),
      performSpaceSwitchGesture(phase: .ended, direction: direction)
    else {
      return false
    }

    return true
  }

  private func performSpaceSwitchGesture(phase: CGSGesturePhase, direction: Direction) -> Bool {
    guard let dockControlEvent = CGEvent(source: nil), let gestureEvent = CGEvent(source: nil) else {
      return false
    }

    dockControlEvent.type = .dockControl
    dockControlEvent.setIntegerValueField(.cgsEventType, value: Int64(CGEventType.dockControl.rawValue))
    dockControlEvent.setIntegerValueField(.gestureHIDType, value: IOHIDEventType.dockSwipe.rawValue)
    dockControlEvent.setIntegerValueField(.gesturePhase, value: phase.rawValue)
    dockControlEvent.setIntegerValueField(.scrollGestureFlagBits, value: direction == .right ? 1 : 0)
    dockControlEvent.setIntegerValueField(.gestureSwipeMotion, value: CGGestureMotion.horizontal.rawValue)
    dockControlEvent.setDoubleValueField(.gestureScrollY, value: 0.0)
    dockControlEvent.setDoubleValueField(.gestureZoomDeltaX, value: Double(Float.leastNonzeroMagnitude))

    if phase == .ended {
      dockControlEvent.setDoubleValueField(.gestureSwipeProgress, value: direction == .right ? 2.0 : -2.0)
      dockControlEvent.setDoubleValueField(.gestureSwipeVelocityX, value: direction == .right ? 400.0 : -400.0)
      dockControlEvent.setDoubleValueField(.gestureSwipeVelocityY, value: 0.0)
    }

    gestureEvent.type = .gesture
    gestureEvent.setIntegerValueField(.cgsEventType, value: Int64(CGEventType.gesture.rawValue))

    dockControlEvent.post(tap: .cgSessionEventTap)
    gestureEvent.post(tap: .cgSessionEventTap)

    return true
  }
}

@MainActor
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
    case .left: spaceSwitcher?.switchSpace(direction: .left)
    case .right: spaceSwitcher?.switchSpace(direction: .right)
    case .space(let number): spaceSwitcher?.switchToSpace(index: number - 1)
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

enum IPCCommand: RawRepresentable, CaseIterable {
  case left
  case right
  case space(Int)
  case quit

  static let notificationName = Notification.Name("\(Configuration.subsystem).IPCCommand")
  static let notificationUserInfoKey = "command"
  static let validSpaceRange = 1...9

  static var allCases: [IPCCommand] { [.left, .right] + validSpaceRange.map { .space($0) } + [.quit] }

  var rawValue: String {
    switch self {
    case .left: "left"
    case .right: "right"
    case .space(let number): String(number)
    case .quit: "quit"
    }
  }

  init?(rawValue: String) {
    switch rawValue.lowercased() {
    case "left":
      self = .left

    case "right":
      self = .right

    case "quit":
      self = .quit

    default:
      guard let number = Int(rawValue), Self.validSpaceRange.contains(number) else {
        return nil
      }

      self = .space(number)
    }
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
