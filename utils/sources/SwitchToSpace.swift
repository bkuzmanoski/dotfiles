import AppKit
import System

enum Configuration {
  static let subsystem = "industries.britown.SwitchToSpace"
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
      print(
        "Failed to close lock file descriptor: \(error.localizedDescription)",
        to: &FileDescriptorOutputStream.standardError
      )
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

enum CGGestureMotion: Int64 {
  case horizontal = 1
}

final class SpaceSwitcher {
  enum Error: Swift.Error, CustomStringConvertible {
    case accessibilityPermissionNotGranted

    var description: String {
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

  private func performSpaceSwitchGesture(phase: CGGesturePhase, direction: Direction) -> Bool {
    guard let dockControlEvent = CGEvent(source: nil), let gestureEvent = CGEvent(source: nil) else {
      return false
    }

    dockControlEvent.type = .dockControl
    dockControlEvent.setIntegerValueField(.cgsEventType, value: Int64(CGEventType.dockControl.rawValue))
    dockControlEvent.setIntegerValueField(.gestureHIDType, value: IOHIDEventType.dockSwipe.rawValue)
    dockControlEvent.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
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
      print(error.localizedDescription, to: &FileDescriptorOutputStream.standardError)
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
    case .left: spaceSwitcher?.switchSpace(direction: .left)
    case .right: spaceSwitcher?.switchSpace(direction: .right)
    case .space(let number): spaceSwitcher?.switchToSpace(index: number - 1)
    case .printLog: break
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: RawRepresentable, CaseIterable {
  case left
  case right
  case space(Int)
  case printLog
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
    case .printLog: "print-log"
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
        print("Failed to redirect output: \(error.localizedDescription)", to: &FileDescriptorOutputStream.standardError)
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

    print("Log file path: \(logFileURL.path)\n")

    do {
      let logContents = try String(contentsOf: logFileURL, encoding: .utf8)

      if logContents.isEmpty {
        print("<EMPTY>")
      } else {
        print(logContents)
      }
    } catch {
      print("Failed to read log file: \(error.localizedDescription)", to: &FileDescriptorOutputStream.standardError)
      exit(EXIT_FAILURE)
    }
  } else {
    ipcCommand.send()
  }

  exit(EXIT_SUCCESS)

} catch {
  print(error.localizedDescription, to: &FileDescriptorOutputStream.standardError)
  exit(EXIT_FAILURE)
}
