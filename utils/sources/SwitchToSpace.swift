// Shared: Accessibility Agent CGEvent Log Spaces

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.SwitchToSpace"
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

  private let startDate = Date.now

  init() throws {
    try AccessibilityPermission.ensureGranted()
  }

  func switchSpace(direction: Direction) {
    guard
      let displaySpaces = NSScreen.main?.displaySpaces,
      let currentSpaceIndex = displaySpaces.currentSpaceIndex
    else {
      return
    }

    let offset = direction == .right ? 1 : -1
    let spaceCount = displaySpaces.spaceIDs.count
    let targetSpaceIndex = (currentSpaceIndex + offset + spaceCount) % spaceCount

    performSwitch(to: targetSpaceIndex, in: displaySpaces)
  }

  func switchToSpace(index spaceIndex: Int) {
    guard let displaySpaces = NSScreen.main?.displaySpaces else {
      return
    }

    performSwitch(to: spaceIndex, in: displaySpaces)
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AccessibilityPermission.isGranted)
      """
    )
  }

  private func performSwitch(to spaceIndex: Int, in displaySpaces: DisplaySpaces) {
    guard let currentSpaceIndex = displaySpaces.currentSpaceIndex else {
      return
    }

    let targetSpaceIndex = min(max(spaceIndex, 0), displaySpaces.spaceIDs.count - 1)

    guard currentSpaceIndex != targetSpaceIndex else {
      return
    }

    let direction: Direction = currentSpaceIndex < targetSpaceIndex ? .right : .left
    let steps = abs(targetSpaceIndex - currentSpaceIndex)

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

  private func performSpaceSwitchGesture(phase gesturePhase: CGGesturePhase, sign: Double) -> Bool {
    let gestureSwipeProgress = sign * 1.6e-5
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
