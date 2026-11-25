// Shared: Accessibility Agent CGEvent Comparable Log NSScreen SkyLightFramework Spaces WindowManagerOverlay

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.SwitchToSpace"
  static let spaceChangeTimeout: Duration = .seconds(2)
  static let spaceChangePollInterval: Duration = .milliseconds(10)
}

enum ScrollDirection {
  case natural
  case classic

  static let didChangeNotification = Notification.Name("SwipeScrollDirectionDidChangeNotification")

  private static let preferenceKey = "com.apple.swipescrolldirection"

  static var current: ScrollDirection {
    CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
    return CFPreferencesCopyAppValue(preferenceKey as CFString, kCFPreferencesAnyApplication) as? Bool ?? true
      ? .natural
      : .classic
  }
}

struct IOFixedPoint: RawRepresentable {
  static let leastNonzeroMagnitude = IOFixedPoint(rawValue: 1)
  static let min = IOFixedPoint(rawValue: .min)
  static let max = IOFixedPoint(rawValue: .max)

  private static let fractionalBits = 16
  private static let scale = Double(1 << fractionalBits)

  let rawValue: IOFixed

  init(rawValue: IOFixed) {
    self.rawValue = rawValue
  }

  init(clamping value: Double) {
    let scaled = (value * Self.scale).rounded(.towardZero)
    self.rawValue = IOFixed(scaled.clamped(to: Double(IOFixed.min)...Double(IOFixed.max)))
  }

  static prefix func - (value: IOFixedPoint) -> IOFixedPoint {
    return IOFixedPoint(rawValue: value.rawValue == .min ? .max : -value.rawValue)
  }
}

struct DockSwipeEvent {
  private static let size = 0x44
  private static let sizeWithVelocity = 0x60
  private static let cgEventDataKey: UInt16 = 0x106d
  private static let dockSwipeEventSize: UInt32 = 0x28
  private static let velocityEventSize: UInt32 = 0x1c
  private static let dockSwipeFlavor: UInt16 = 3
  private static let positionX = IOFixedPoint(clamping: 0.1)

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

  var cgEvent: CGEvent? {
    guard let event = CGEvent(source: nil) else {
      return nil
    }

    event.cgsEventType = .dockControl

    guard var eventData = event.data as Data? else {
      return nil
    }

    withUnsafeBytes(of: UInt16(bytes.count).bigEndian) { eventData.append(contentsOf: $0) }
    withUnsafeBytes(of: Self.cgEventDataKey.bigEndian) { eventData.append(contentsOf: $0) }
    eventData.append(contentsOf: bytes)

    return CGEvent(withDataAllocator: nil, data: eventData as CFData)
  }

  init(
    timestamp: UInt64 = mach_absolute_time(),
    phase gesturePhase: CGGesturePhase,
    progress dockSwipeProgress: IOFixedPoint,
    velocityX: IOFixedPoint? = nil
  ) {
    self.bytes = [UInt8](repeating: 0, count: velocityX == nil ? Self.size : Self.sizeWithVelocity)

    setValue(timestamp, at: Offset.timestamp)
    setValue(UInt32(velocityX == nil ? 1 : 2), at: Offset.eventCount)
    setValue(Self.dockSwipeEventSize, at: Offset.dockSwipeEventSize)
    setValue(IOHIDEventType.dockSwipe.rawValue, at: Offset.dockSwipeEventType)
    setValue(gesturePhase.rawValue << 24, at: Offset.dockSwipeOptions)
    setValue(Self.positionX.rawValue, at: Offset.dockSwipePositionX)
    setValue(IOHIDGestureMotion.horizontal.rawValue, at: Offset.dockSwipeMotion)
    setValue(Self.dockSwipeFlavor, at: Offset.dockSwipeFlavor)
    setValue(dockSwipeProgress.rawValue, at: Offset.dockSwipeProgress)

    if let velocityX {
      setValue(Self.velocityEventSize, at: Offset.velocityEventSize)
      setValue(IOHIDEventType.velocity.rawValue, at: Offset.velocityEventType)
      setValue(UInt32(1), at: Offset.velocityEventDepth)
      setValue(velocityX.rawValue, at: Offset.velocityX)
    }
  }

  private mutating func setValue<T: FixedWidthInteger>(_ value: T, at offset: Int) {
    bytes.withUnsafeMutableBytes { $0.storeBytes(of: value.littleEndian, toByteOffset: offset, as: T.self) }
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

  private enum SwitchError: Error, LocalizedError {
    case failedToCreateEvent
    case timedOut

    var errorDescription: String? {
      switch self {
      case .failedToCreateEvent: "Failed to create space switch gesture event."
      case .timedOut: "Timed out waiting for space switch."
      }
    }
  }

  private let startDate = Date.now
  private let skyLightFramework: SkyLightFramework
  private var pendingRequest: SwitchRequest?
  private var spaceSwitchTask: Task<Void, Never>?
  private var scrollDirection: ScrollDirection = .current
  private var scrollDirectionObservationTask: Task<Void, Never>?
  private var timeoutCount = 0
  private var lastTimeoutDate: Date?

  private var isSpaceSwitchingBlocked: Bool {
    switch WindowManagerOverlay.onScreen {
    case .appExpose, .showDesktop: true // App Exposé and Show Desktop don't switch spaces on Dock swipes.
    case .missionControl, nil: false
    }
  }

  init() throws {
    try AccessibilityPermission.ensureGranted()

    self.skyLightFramework = try SkyLightFramework()

    self.scrollDirectionObservationTask = Task { [weak self] in
      for await _ in DistributedNotificationCenter.default().notifications(
        named: ScrollDirection.didChangeNotification
      ) {
        guard let self else {
          break
        }

        self.scrollDirection = .current
      }
    }
  }

  isolated deinit {
    spaceSwitchTask?.cancel()
    scrollDirectionObservationTask?.cancel()
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
        Space switch in progress: \(spaceSwitchTask != nil)
        Scroll direction: \(scrollDirection)
        Timeouts: \(timeoutCount)
        Last timeout: \(lastTimeoutDate?.formatted(.dateTime) ?? "never")
      """
    )
  }

  private func displaySpacesContainingMouse() -> DisplaySpaces? {
    return NSScreen.screenContainingMouse.flatMap { skyLightFramework.displaySpaces(for: $0) }
  }

  private func requestSwitch(to spaceIndex: Int, in displaySpaces: DisplaySpaces) {
    guard !displaySpaces.spaceIDs.isEmpty else {
      return
    }

    let targetSpaceIndex = spaceIndex.clamped(to: 0...(displaySpaces.spaceIDs.count - 1))

    self.pendingRequest = SwitchRequest(
      displayIdentifier: displaySpaces.displayIdentifier,
      targetSpaceIndex: targetSpaceIndex
    )

    guard spaceSwitchTask == nil else {
      return
    }

    self.spaceSwitchTask = Task { [weak self] in
      await self?.processPendingRequests()
    }
  }

  // Sends all swipes for a request at once, allowing the Dock to combine them into one transition. Waits for that
  // transition to finish before processing the latest request, coalescing rapid input without overlapping transitions.
  private func processPendingRequests() async {
    defer {
      self.pendingRequest = nil
      self.spaceSwitchTask = nil
    }

    while let request = pendingRequest, !Task.isCancelled {
      guard
        !isSpaceSwitchingBlocked,
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

      do {
        try await performSpaceSwitchGestures(from: currentSpaceIndex, to: targetSpaceIndex, in: displaySpaces)

      } catch is CancellationError {
        return

      } catch {
        if case SwitchError.timedOut = error {
          self.timeoutCount += 1
          self.lastTimeoutDate = .now
        }

        Log.error(error.localizedDescription)

        return
      }
    }
  }

  private func performSpaceSwitchGestures(
    from currentSpaceIndex: Int,
    to targetSpaceIndex: Int,
    in displaySpaces: DisplaySpaces
  ) async throws {
    let isLeftwardSwipe = (currentSpaceIndex < targetSpaceIndex) == (scrollDirection == .natural)
    let progress = isLeftwardSwipe ? -IOFixedPoint.leastNonzeroMagnitude : IOFixedPoint.leastNonzeroMagnitude
    let velocityX = isLeftwardSwipe ? -IOFixedPoint.max : IOFixedPoint.max

    for _ in 0..<abs(targetSpaceIndex - currentSpaceIndex) {
      try post(DockSwipeEvent(phase: .began, progress: progress))

      do {
        try post(DockSwipeEvent(phase: .ended, progress: progress, velocityX: velocityX))
      } catch {
        try? post(DockSwipeEvent(phase: .cancelled, progress: progress))
        throw error
      }
    }

    try await waitForCurrentSpace(displaySpaces.spaceIDs[targetSpaceIndex], on: displaySpaces.displayIdentifier)
  }

  private func waitForCurrentSpace(_ spaceID: SpaceID, on displayIdentifier: DisplayIdentifier) async throws {
    let deadline = ContinuousClock.now + Configuration.spaceChangeTimeout

    while ContinuousClock.now < deadline {
      try await Task.sleep(for: Configuration.spaceChangePollInterval)

      if skyLightFramework.displaySpaces(for: displayIdentifier)?.currentSpaceID == spaceID {
        return
      }
    }

    try Task.checkCancellation()

    throw SwitchError.timedOut
  }

  private func post(_ event: DockSwipeEvent) throws(SwitchError) {
    guard let cgEvent = event.cgEvent else {
      throw .failedToCreateEvent
    }

    cgEvent.post(tap: .cgSessionEventTap)
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
