import AppKit

enum Constants {
  static let subsystem = "industries.britown.FocusFollowsMouse"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let hoverDelay: DispatchTimeInterval = .milliseconds(150)
}

enum ProcessSignals {
  static func stream(for signals: [CInt]) -> AsyncStream<CInt> {
    let sources = signals.map { signal in
      DispatchSource.makeSignalSource(signal: signal, queue: .main)
    }

    let (stream, continuation) = AsyncStream.makeStream(of: CInt.self)

    for (signal, source) in zip(signals, sources) {
      source.setEventHandler {
        continuation.yield(signal)
      }

      source.resume()
    }

    continuation.onTermination = { _ in
      sources.forEach { $0.cancel() }
    }

    return stream
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
      case .instanceAlreadyRunning: return "Instance already running."
      case .failedToAcquireLock(let errno): return "Failed to acquire lock (\(String(cString: strerror(errno))))."
      }
    }
  }

  private let lockFilePath = FileManager.default.temporaryDirectory.appendingPathComponent(Constants.lockFileName).path
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

struct ProcessSerialNumber {
  var highLongOfPSN: UInt32 = 0
  var lowLongOfPSN: UInt32 = 0
}

@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

@_silgen_name("SameProcess")
func SameProcess(
  _ psn1: UnsafePointer<ProcessSerialNumber>,
  _ psn2: UnsafePointer<ProcessSerialNumber>,
  _ result: UnsafeMutablePointer<DarwinBoolean>
) -> OSStatus

@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
  static var systemWide: AXUIElement { AXUIElementCreateSystemWide() }

  var pid: pid_t? {
    var pid: pid_t = 0
    return AXUIElementGetPid(self, &pid) == .success ? pid : nil
  }

  var windowID: CGWindowID? {
    var windowID: CGWindowID = kCGNullWindowID
    return _AXUIElementGetWindow(self, &windowID) == .success ? windowID : nil
  }

  static func element(at point: CGPoint) -> AXUIElement? {
    var element: AXUIElement?
    return AXUIElementCopyElementAtPosition(
      AXUIElement.systemWide,
      Float(point.x),
      Float(point.y),
      &element
    ) == .success
      ? element
      : nil
  }

  func value<T>(for attribute: NSAccessibility.Attribute, as type: T.Type = T.self) -> T? {
    var rawValue: CFTypeRef?
    return AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &rawValue) == .success
      ? rawValue as? T
      : nil
  }
}

let kCPSUserGenerated: UInt32 = 0x200

struct SLPSEventRecord {
  private static let size = 0xf8

  private enum Offset {
    static let recordLength = 0x04
    static let eventType = 0x08
    static let mask = 0x20
    static let activationFlag = 0x3a
    static let windowID = 0x3c
    static let focusTransitionType = 0x8a
  }

  enum EventType: UInt8 {
    case leftMouseDown = 0x01
    case leftMouseUp = 0x02
    case focusTransition = 0x0d
  }

  enum FocusTransitionType: UInt8 {
    case becomeKey = 0x01
    case resignKey = 0x02
  }

  enum SimulatedClickType {
    case leftMouseDown
    case leftMouseUp

    var eventType: EventType {
      switch self {
      case .leftMouseDown: .leftMouseDown
      case .leftMouseUp: .leftMouseUp
      }
    }
  }

  var bytes: [UInt8]

  private init() {
    self.bytes = [UInt8](repeating: 0, count: Self.size)
    self.bytes[Offset.recordLength] = UInt8(Self.size)
  }

  static func focusTransition(windowID: CGWindowID, type focusTransitionType: FocusTransitionType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = EventType.focusTransition.rawValue
    eventRecord.bytes[Offset.focusTransitionType] = focusTransitionType.rawValue
    eventRecord.setWindowID(windowID)

    return eventRecord
  }

  static func simulatedClick(windowID: CGWindowID, type simulatedClickType: SimulatedClickType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = simulatedClickType.eventType.rawValue
    eventRecord.bytes.replaceSubrange(Offset.mask..<Offset.mask + 0x10, with: repeatElement(0xff, count: 0x10))
    eventRecord.bytes[Offset.activationFlag] = 0x10
    eventRecord.setWindowID(windowID)

    return eventRecord
  }

  private mutating func setWindowID(_ windowID: CGWindowID) {
    let idBytes = withUnsafeBytes(of: windowID) { Array($0) }
    self.bytes.replaceSubrange(Offset.windowID..<Offset.windowID + 4, with: idBytes)
  }
}

struct SkyLightProxy {
  enum Error: Swift.Error, LocalizedError {
    case frameworkNotFound
    case symbolNotFound(String)

    var errorDescription: String? {
      switch self {
      case .frameworkNotFound: "SkyLight framework could not be loaded."
      case .symbolNotFound(let symbol): "Symbol '\(symbol)' not found in SkyLight framework."
      }
    }
  }

  private typealias SLPSPostEventRecordTo = @convention(c) (UnsafeMutableRawPointer, UnsafeMutableRawPointer) -> CGError
  private typealias _SLPSSetFrontProcessWithOptions =
    @convention(c) (
      UnsafeMutableRawPointer,
      CGWindowID,
      UInt32
    ) -> CGError

  private let slpsPostEventRecordTo: SLPSPostEventRecordTo
  private let _slpsSetFrontProcessWithOptions: _SLPSSetFrontProcessWithOptions

  init() throws {
    guard let skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
      throw Error.frameworkNotFound
    }

    guard let slpsPostEventRecordToSymbol = dlsym(skyLightHandle, "SLPSPostEventRecordTo") else {
      throw Error.symbolNotFound("SLPSPostEventRecordTo")
    }

    guard let _slpsSetFrontProcessWithOptionsSymbol = dlsym(skyLightHandle, "_SLPSSetFrontProcessWithOptions") else {
      throw Error.symbolNotFound("_SLPSSetFrontProcessWithOptions")
    }

    self.slpsPostEventRecordTo = unsafeBitCast(slpsPostEventRecordToSymbol, to: SLPSPostEventRecordTo.self)
    self._slpsSetFrontProcessWithOptions = unsafeBitCast(
      _slpsSetFrontProcessWithOptionsSymbol,
      to: _SLPSSetFrontProcessWithOptions.self
    )
  }

  @discardableResult
  func postEventRecordTo(_ psn: inout ProcessSerialNumber, _ record: inout SLPSEventRecord) -> CGError {
    return record.bytes.withUnsafeMutableBufferPointer { slpsPostEventRecordTo(&psn, $0.baseAddress!) }
  }

  func setFrontProcessWithOptions(_ psn: inout ProcessSerialNumber, _ wid: CGWindowID, _ mode: UInt32) -> CGError {
    return _slpsSetFrontProcessWithOptions(&psn, wid, mode)
  }
}

@MainActor
final class FocusManager {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionDenied
    case failedToCreateEventTap

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied: return "Accessibility permission denied."
      case .failedToCreateEventTap: return "Failed to create event tap."
      }
    }
  }

  private(set) var eventTap: CFMachPort?
  private(set) var isEnabled = true

  private let skyLightProxy: SkyLightProxy
  private let debounceTimer: DispatchSourceTimer
  private var runLoopSource: CFRunLoopSource?
  private var lastMouseLocation: CGPoint = .zero
  private var lastMouseMoveTime: DispatchTime = .now()
  private var isTimerPending = false

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }

    self.skyLightProxy = try SkyLightProxy()
    self.debounceTimer = DispatchSource.makeTimerSource(queue: .main)

    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: 1 << CGEventType.mouseMoved.rawValue,
        callback: eventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    debounceTimer.setEventHandler { [weak self] in
      self?.handleTimerEvent()
    }

    self.eventTap = tap
    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

    debounceTimer.resume()
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
  }

  deinit {
    debounceTimer.cancel()

    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFMachPortInvalidate(eventTap)
    }

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }
  }

  func toggleEnabled() {
    guard let eventTap else {
      return
    }

    self.isEnabled.toggle()

    CGEvent.tapEnable(tap: eventTap, enable: isEnabled)
  }

  func handleMouseMoved(to point: CGPoint) {
    guard isEnabled, point != lastMouseLocation else {
      return
    }

    self.lastMouseLocation = point
    self.lastMouseMoveTime = .now()

    if !isTimerPending {
      self.isTimerPending = true
      debounceTimer.schedule(deadline: lastMouseMoveTime + Constants.hoverDelay)
    }
  }

  private func handleTimerEvent() {
    guard self.isEnabled else {
      return
    }

    let targetTime = lastMouseMoveTime + Constants.hoverDelay

    if DispatchTime.now() >= targetTime {
      self.isTimerPending = false

      Task { [weak self, lastMouseLocation] in
        await self?.focusWindow(at: lastMouseLocation)
      }
    } else {
      debounceTimer.schedule(deadline: targetTime)
    }
  }

  private func focusWindow(at point: CGPoint) async {
    guard let hoveredElement = AXUIElement.element(at: point) else {
      return
    }

    if let role = hoveredElement.value(for: .role, as: String.self) {
      guard role != kAXMenuBarRole && role != kAXDockItemRole else {
        return
      }
    }

    let targetWindow = hoveredElement.value(for: .window) ?? hoveredElement

    guard
      let targetWindowID = targetWindow.windowID,
      let targetWindowPID = targetWindow.pid
    else {
      return
    }

    let focusedElement = AXUIElement.systemWide.value(for: .focusedUIElement, as: AXUIElement.self)
    let focusedWindow = focusedElement?.value(for: .window) ?? focusedElement

    if let focusedWindowID = focusedWindow?.windowID, targetWindowID == focusedWindowID {
      return
    }

    var windowPSN = ProcessSerialNumber()

    guard GetProcessForPID(targetWindowPID, &windowPSN) == noErr else {
      return
    }

    if let focusedWindowID = focusedWindow?.windowID, let focusedWindowPID = focusedWindow?.pid {
      var focusedWindowPSN = ProcessSerialNumber()

      if GetProcessForPID(focusedWindowPID, &focusedWindowPSN) == noErr {
        var isSameProcess: DarwinBoolean = false

        if SameProcess(&windowPSN, &focusedWindowPSN, &isSameProcess) == noErr, isSameProcess.boolValue {
          var resignKeyEvent = SLPSEventRecord.focusTransition(windowID: focusedWindowID, type: .resignKey)

          if skyLightProxy.postEventRecordTo(&focusedWindowPSN, &resignKeyEvent) == .success {
            try? await Task.sleep(for: .milliseconds(10))

            var becomeKeyEvent = SLPSEventRecord.focusTransition(windowID: targetWindowID, type: .becomeKey)

            skyLightProxy.postEventRecordTo(&windowPSN, &becomeKeyEvent)
          }
        }
      }
    }

    guard skyLightProxy.setFrontProcessWithOptions(&windowPSN, targetWindowID, kCPSUserGenerated) == .success else {
      return
    }

    var leftMouseDownEvent = SLPSEventRecord.simulatedClick(windowID: targetWindowID, type: .leftMouseDown)

    guard skyLightProxy.postEventRecordTo(&windowPSN, &leftMouseDownEvent) == .success else {
      return
    }

    var leftMouseUpEvent = SLPSEventRecord.simulatedClick(windowID: targetWindowID, type: .leftMouseUp)

    skyLightProxy.postEventRecordTo(&windowPSN, &leftMouseUpEvent)
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

  let focusManager = Unmanaged<FocusManager>.fromOpaque(refcon).takeUnretainedValue()

  return MainActor.assumeIsolated {
    switch type {
    case .mouseMoved:
      focusManager.handleMouseMoved(to: event.location)

    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if focusManager.isEnabled, let eventTap = focusManager.eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }

    default:
      break
    }

    return Unmanaged.passUnretained(event)
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var focusManager: FocusManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.focusManager = try FocusManager()
    } catch {
      FileHandle.standardError.write(Data("Failed to initialize FocusManager: \(error.localizedDescription)\n".utf8))
      NSApplication.shared.terminate(nil)

      return
    }

    observeSignals()
    observeCommands()
  }

  private func observeSignals() {
    Task {
      for await _ in ProcessSignals.stream(for: [SIGHUP, SIGINT, SIGTERM]) {
        NSApplication.shared.terminate(nil)
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

        handleCommand(with: arguments)
      }
    }
  }

  private func handleCommand(with arguments: [String]) {
    guard let command = arguments.first else {
      return
    }

    switch command {
    case "toggle": focusManager?.toggleEnabled()
    case "quit": NSApplication.shared.terminate(nil)
    default: return
    }
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
  let arguments = Array(CommandLine.arguments.dropFirst())

  guard !arguments.isEmpty else {
    print("Already running, specify \"toggle\" or \"quit\" as an argument.")
    exit(0)
  }

  Command(arguments: arguments).send()
  exit(0)

} catch {
  FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
