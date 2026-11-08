// Shared: Accessibility Agent CGEvent Log NSScreen SkyLightFramework Spaces

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.SwitchToSpace"
  static let spaceChangeTimeout: Duration = .seconds(2)
  static let spaceChangePollInterval: Duration = .milliseconds(10)
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

  init(gesturePhase: CGGesturePhase, progress dockSwipeProgress: Double, velocityX: Double?) {
    self.bytes = [UInt8](repeating: 0, count: velocityX == nil ? Self.size : Self.sizeWithVelocity)

    setValue(mach_absolute_time(), at: Offset.timestamp)
    setValue(UInt32(velocityX == nil ? 1 : 2), at: Offset.eventCount)
    setValue(Self.dockSwipeEventSize, at: Offset.dockSwipeEventSize)
    setValue(IOHIDEventType.dockSwipe.rawValue, at: Offset.dockSwipeEventType)
    setValue(gesturePhase.rawValue << 24, at: Offset.dockSwipeOptions)
    setValue(Self.fixedPoint(Self.positionX), at: Offset.dockSwipePositionX)
    setValue(IOHIDGestureMotion.horizontal.rawValue, at: Offset.dockSwipeMotion)
    setValue(Self.dockSwipeFlavor, at: Offset.dockSwipeFlavor)
    setValue(Self.fixedPoint(dockSwipeProgress), at: Offset.dockSwipeProgress)

    if let velocityX {
      setValue(Self.velocityEventSize, at: Offset.velocityEventSize)
      setValue(IOHIDEventType.velocity.rawValue, at: Offset.velocityEventType)
      setValue(UInt32(1), at: Offset.velocityEventDepth)
      setValue(Self.fixedPoint(velocityX), at: Offset.velocityX)
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

@MainActor
final class SpaceSwitcher {
  enum Direction {
    case left
    case right
  }

  private struct SwitchRequest {
    let displayIdentifier: DisplayIdentifier
    let targetSpaceIndex: Int
  }

  private let startDate = Date.now
  private let skyLightFramework: SkyLightFramework
  private var pendingRequest: SwitchRequest?
  private var switchTask: Task<Void, Never>?
  private var timeoutCount = 0
  private var lastTimeoutDate: Date?

  init() throws {
    try AccessibilityPermission.ensureGranted()
    self.skyLightFramework = try SkyLightFramework()
  }

  isolated deinit {
    switchTask?.cancel()
  }

  func switchSpace(direction: Direction) {
    guard let displaySpaces = displaySpacesContainingMouse() else {
      return
    }

    let pendingTargetSpaceIndex = pendingRequest.flatMap {
      $0.displayIdentifier == displaySpaces.displayIdentifier ? $0.targetSpaceIndex : nil
    }

    guard let baseSpaceIndex = pendingTargetSpaceIndex ?? displaySpaces.currentSpaceIndex else {
      return
    }

    let offset = direction == .right ? 1 : -1
    let spaceCount = displaySpaces.spaceIDs.count

    requestSwitch(to: (baseSpaceIndex + offset + spaceCount) % spaceCount, in: displaySpaces)
  }

  func switchToSpace(index spaceIndex: Int) {
    guard let displaySpaces = displaySpacesContainingMouse() else {
      return
    }

    requestSwitch(to: spaceIndex, in: displaySpaces)
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AccessibilityPermission.isGranted)
        Switch in progress: \(switchTask != nil)
        Timeouts: \(timeoutCount)
        Last timeout: \(lastTimeoutDate?.formatted(.dateTime) ?? "never")
      """
    )
  }

  private func displaySpacesContainingMouse() -> DisplaySpaces? {
    return NSScreen.screenContainingMouse.flatMap { skyLightFramework.displaySpaces(for: $0) }
  }

  private func requestSwitch(to spaceIndex: Int, in displaySpaces: DisplaySpaces) {
    let targetSpaceIndex = min(max(spaceIndex, 0), displaySpaces.spaceIDs.count - 1)

    self.pendingRequest = SwitchRequest(
      displayIdentifier: displaySpaces.displayIdentifier,
      targetSpaceIndex: targetSpaceIndex
    )

    guard switchTask == nil else {
      return
    }

    self.switchTask = Task { [weak self] in
      await self?.processPendingRequests()
    }
  }

  // Sends all swipes for a request at once, allowing the Dock to combine them into one transition. Waits for that
  // transition to finish before processing the latest request, coalescing rapid input without overlapping transitions.
  private func processPendingRequests() async {
    defer {
      self.pendingRequest = nil
      self.switchTask = nil
    }

    while let request = pendingRequest, !Task.isCancelled {
      guard
        NSScreen.screenContainingMouse?.displayIdentifier == request.displayIdentifier,
        let displaySpaces = skyLightFramework.displaySpaces(for: request.displayIdentifier),
        let currentSpaceIndex = displaySpaces.currentSpaceIndex
      else {
        return
      }

      let targetSpaceIndex = min(request.targetSpaceIndex, displaySpaces.spaceIDs.count - 1)

      guard currentSpaceIndex != targetSpaceIndex else {
        return
      }

      guard
        await performSpaceSwitchGestures(
          direction: currentSpaceIndex < targetSpaceIndex ? .right : .left,
          count: abs(targetSpaceIndex - currentSpaceIndex),
          toward: displaySpaces.spaceIDs[targetSpaceIndex],
          on: request.displayIdentifier
        )
      else {
        return
      }
    }
  }

  private func performSpaceSwitchGestures(
    direction: Direction,
    count: Int,
    toward targetSpaceID: SpaceID,
    on displayIdentifier: DisplayIdentifier
  ) async -> Bool {
    let isNaturalScrolling = UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    let sign: Double = (direction == .right) == isNaturalScrolling ? -1.0 : 1.0

    for _ in 0..<count {
      guard postDockSwipeEvent(phase: .began, sign: sign) else {
        return false
      }

      guard postDockSwipeEvent(phase: .ended, sign: sign) else {
        postDockSwipeEvent(phase: .cancelled, sign: sign)
        return false
      }
    }

    guard await waitForCurrentSpace(targetSpaceID, on: displayIdentifier) else {
      if !Task.isCancelled {
        self.timeoutCount += 1
        self.lastTimeoutDate = .now

        Log.error("Timed out waiting for space switch.")
      }

      postDockSwipeEvent(phase: .cancelled, sign: sign)

      return false
    }

    return true
  }

  private func waitForCurrentSpace(_ spaceID: SpaceID, on displayIdentifier: DisplayIdentifier) async -> Bool {
    let deadline = ContinuousClock.now + Configuration.spaceChangeTimeout

    while ContinuousClock.now < deadline {
      do {
        try await Task.sleep(for: Configuration.spaceChangePollInterval)
      } catch {
        return false
      }

      if skyLightFramework.displaySpaces(for: displayIdentifier)?.currentSpaceID == spaceID {
        return true
      }
    }

    return false
  }

  @discardableResult
  private func postDockSwipeEvent(phase gesturePhase: CGGesturePhase, sign: Double) -> Bool {
    let gestureSwipeProgress = gesturePhase == .cancelled ? 0.0 : sign * 1.6e-5
    let velocityX: Double? = gesturePhase == .ended ? sign * 500.0 : nil

    guard let dockControlEvent = CGEvent(source: nil) else {
      Log.error("Failed to create CGEvent for space switch gesture.")
      return false
    }

    dockControlEvent.cgsEventType = .dockControl
    dockControlEvent.gestureHIDType = .dockSwipe
    dockControlEvent.gesturePhase = gesturePhase
    dockControlEvent.gestureSwipeMotion = .horizontal
    dockControlEvent.gestureSwipeProgress = gestureSwipeProgress

    if let velocityX {
      dockControlEvent.gestureSwipeVelocityX = velocityX
    }

    guard
      let hidDockControlEvent = DockSwipeHIDEvent(
        gesturePhase: gesturePhase,
        progress: gestureSwipeProgress,
        velocityX: velocityX
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
final class AppDelegate: NSObject, AgentDelegate {
  private var spaceSwitcher: SpaceSwitcher?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.spaceSwitcher = try SpaceSwitcher()
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.spaceSwitcher = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .left: spaceSwitcher?.switchSpace(direction: .left)
    case .right: spaceSwitcher?.switchSpace(direction: .right)
    case .space(let number): spaceSwitcher?.switchToSpace(index: number - 1)
    case .printLog: spaceSwitcher?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: AgentIPCCommand {
  case left
  case right
  case space(Int)
  case printLog
  case quit

  static let validSpaceRange = 1...9

  static var allCases: [IPCCommand] { [.left, .right] + validSpaceRange.map { .space($0) } + [.printLog, .quit] }

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
}

@main
enum SwitchToSpace {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
