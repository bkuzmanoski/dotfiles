import AppKit
import Synchronization
import System

enum Configuration {
  static let subsystem = "industries.britown.SwitchToSpace"
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
      for source in sources {
        source.cancel()
      }
    }

    return stream
  }
}

typealias CGSConnectionID = UInt32

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connectionID: CGSConnectionID, _ displayIdentifier: CFString?) -> Unmanaged<CFArray>?

extension CGEventField {
  static let cgsEventType = CGEventField(rawValue: 55)!
  static let gestureHIDType = CGEventField(rawValue: 110)!
  static let gestureSwipeMotion = CGEventField(rawValue: 123)!
  static let gestureSwipeProgress = CGEventField(rawValue: 124)!
  static let gestureSwipeVelocityX = CGEventField(rawValue: 129)!
  static let gesturePhase = CGEventField(rawValue: 132)!
}

extension CGEventType {
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

enum IOHIDEventType: UInt32 {
  case velocity = 9
  case dockSwipe = 23
}

enum IOHIDGestureMotion: UInt16 {
  case horizontal = 1
}

struct DockSwipeHIDEvent {
  private static let size = 0x44
  private static let sizeWithVelocity = 0x60
  private static let cgEventDataKey: UInt16 = 0x106d
  private static let dockSwipeEventSize: UInt32 = 0x28
  private static let velocityEventSize: UInt32 = 0x1c
  private static let dockSwipeFlavor: UInt16 = 3
  private static let positionX = 0.1

  private enum Offset {
    static let timestamp = 0x00
    static let eventCount = 0x18
    static let dockSwipeEventSize = 0x1c
    static let dockSwipeEventType = 0x20
    static let dockSwipeOptions = 0x24
    static let dockSwipePositionX = 0x2c
    static let dockSwipeMotion = 0x3c
    static let dockSwipeFlavor = 0x3e
    static let dockSwipeProgress = 0x40
    static let velocityEventSize = 0x44
    static let velocityEventType = 0x48
    static let velocityEventDepth = 0x50
    static let velocityX = 0x54
  }

  private var bytes: [UInt8]

  init(phase: CGGesturePhase, progress: Double, velocity: Double?) {
    self.bytes = [UInt8](repeating: 0, count: velocity == nil ? Self.size : Self.sizeWithVelocity)

    setValue(mach_absolute_time(), at: Offset.timestamp)
    setValue(UInt32(velocity == nil ? 1 : 2), at: Offset.eventCount)
    setValue(Self.dockSwipeEventSize, at: Offset.dockSwipeEventSize)
    setValue(IOHIDEventType.dockSwipe.rawValue, at: Offset.dockSwipeEventType)
    setValue(phase.rawValue << 24, at: Offset.dockSwipeOptions)
    setValue(Self.fixedPoint(Self.positionX), at: Offset.dockSwipePositionX)
    setValue(IOHIDGestureMotion.horizontal.rawValue, at: Offset.dockSwipeMotion)
    setValue(Self.dockSwipeFlavor, at: Offset.dockSwipeFlavor)
    setValue(Self.fixedPoint(progress), at: Offset.dockSwipeProgress)

    if let velocity {
      setValue(Self.velocityEventSize, at: Offset.velocityEventSize)
      setValue(IOHIDEventType.velocity.rawValue, at: Offset.velocityEventType)
      setValue(UInt32(1), at: Offset.velocityEventDepth)
      setValue(Self.fixedPoint(velocity), at: Offset.velocityX)
    }
  }

  func attach(to event: CGEvent) -> CGEvent? {
    guard var eventData = event.data as Data? else {
      return nil
    }

    withUnsafeBytes(of: UInt16(bytes.count).bigEndian) { eventData.append(contentsOf: $0) }
    withUnsafeBytes(of: Self.cgEventDataKey.bigEndian) { eventData.append(contentsOf: $0) }
    eventData.append(contentsOf: bytes)

    return CGEvent(withDataAllocator: nil, data: eventData as CFData)
  }

  private mutating func setValue<T: FixedWidthInteger>(_ value: T, at offset: Int) {
    bytes.withUnsafeMutableBytes { $0.storeBytes(of: value.littleEndian, toByteOffset: offset, as: T.self) }
  }

  private static func fixedPoint(_ value: Double) -> Int32 {
    let fixedPointValue = Int32((value * 65536).rounded(.towardZero))
    return fixedPointValue == 0 && value != 0 ? (value < 0 ? -1 : 1) : fixedPointValue
  }
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

  private let startDate = Date.now

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

  func logDiagnosticReport() {
    Log.message(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AXIsProcessTrustedWithOptions(nil))
      """
    )
  }

  private func performSwitch(to index: Int, spacesInfo: (spaceCount: Int, currentIndex: Int)) {
    let targetIndex = min(max(index, 0), spacesInfo.spaceCount - 1)

    guard spacesInfo.currentIndex != targetIndex else {
      return
    }

    let direction: Direction = spacesInfo.currentIndex < targetIndex ? .right : .left
    let steps = direction == .right ? (targetIndex - spacesInfo.currentIndex) : (spacesInfo.currentIndex - targetIndex)

    for _ in 0..<steps where !performSpaceSwitchGesture(direction: direction) {
      return
    }
  }

  @discardableResult
  private func performSpaceSwitchGesture(direction: Direction) -> Bool {
    let isNaturalScrolling = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    let sign: Double = (direction == .right) == isNaturalScrolling ? -1.0 : 1.0

    guard
      performSpaceSwitchGesture(phase: .began, sign: sign),
      performSpaceSwitchGesture(phase: .ended, sign: sign)
    else {
      return false
    }

    return true
  }

  private func performSpaceSwitchGesture(phase: CGGesturePhase, sign: Double) -> Bool {
    let progress = sign * 1.6e-5
    let velocity: Double? = phase == .ended ? sign * 500.0 : nil

    guard let dockControlEvent = CGEvent(source: nil) else {
      Log.error("Failed to create CGEvent for space switch gesture.")
      return false
    }

    dockControlEvent.setIntegerValueField(.cgsEventType, value: Int64(CGEventType.dockControl.rawValue))
    dockControlEvent.setIntegerValueField(.gestureHIDType, value: Int64(IOHIDEventType.dockSwipe.rawValue))
    dockControlEvent.setIntegerValueField(.gesturePhase, value: Int64(phase.rawValue))
    dockControlEvent.setIntegerValueField(.gestureSwipeMotion, value: Int64(IOHIDGestureMotion.horizontal.rawValue))
    dockControlEvent.setDoubleValueField(.gestureSwipeProgress, value: progress)

    if let velocity {
      dockControlEvent.setDoubleValueField(.gestureSwipeVelocityX, value: velocity)
    }

    guard
      let hidDockControlEvent = DockSwipeHIDEvent(
        phase: phase,
        progress: progress,
        velocity: velocity
      ).attach(to: dockControlEvent)
    else {
      Log.error("Failed to attach HID event data to space switch gesture.")
      return false
    }

    hidDockControlEvent.post(tap: .cgSessionEventTap)

    return true
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var singleInstanceLock: SingleInstanceLock?
  private var spaceSwitcher: SpaceSwitcher?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.spaceSwitcher = try SpaceSwitcher()
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }

    observeProcessSignals()
    observeIPCCommands()
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.singleInstanceLock = nil
    self.spaceSwitcher = nil
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
      for await notification in DistributedNotificationCenter.default().notifications(
        named: IPCCommand.notificationName
      ) {
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
    case .printLog: spaceSwitcher?.logDiagnosticReport()
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

    case "print-log":
      self = .printLog

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
