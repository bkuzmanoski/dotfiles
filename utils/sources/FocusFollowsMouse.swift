import AppKit
import Synchronization
import System

enum Configuration {
  static let subsystem = "industries.britown.FocusFollowsMouse"
  static let hoverDelay: DispatchTimeInterval = .milliseconds(200)
  static let jitterThreshold = 3
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

extension NSRunningApplication {
  var isSystemAgent: Bool {
    activationPolicy != .regular && bundleURL?.path.hasPrefix("/System/") == true
  }
}

struct ProcessSerialNumber {
  var highLongOfPSN: UInt32 = 0
  var lowLongOfPSN: UInt32 = 0
}

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("GetProcessForPID")
func GetProcessForPID(_ pid: pid_t, _ psn: UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus

// swift-format-ignore: AlwaysUseLowerCamelCase
@_silgen_name("SameProcess")
func SameProcess(
  _ psn1: UnsafePointer<ProcessSerialNumber>,
  _ psn2: UnsafePointer<ProcessSerialNumber>,
  _ result: UnsafeMutablePointer<DarwinBoolean>
) -> OSStatus

// swift-format-ignore: NoLeadingUnderscores
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
  enum Error: Swift.Error, LocalizedError {
    case typeMismatch

    var errorDescription: String? {
      switch self {
      case .typeMismatch: "Returned value type does not match expected type."
      }
    }
  }

  static func setGlobalMessagingTimeout(seconds timeoutInSeconds: Float) {
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeoutInSeconds)
  }

  func windowID() throws -> CGWindowID {
    var windowID: CGWindowID = kCGNullWindowID

    try _AXUIElementGetWindow(self, &windowID).throwIfFailed()

    return windowID
  }

  func value<T>(for attribute: NSAccessibility.Attribute, as type: T.Type = T.self) throws -> T {
    var rawValue: CFTypeRef?

    try AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &rawValue).throwIfFailed()

    guard let value = rawValue as? T else {
      throw Error.typeMismatch
    }

    return value
  }
}

extension AXError: @retroactive _BridgedNSError, @retroactive Error, @retroactive LocalizedError {
  public var errorDescription: String? {
    let message: String

    switch self {
    case .success: message = "Success"
    case .failure: message = "Failure"
    case .illegalArgument: message = "Illegal argument"
    case .invalidUIElement: message = "Invalid UI element"
    case .invalidUIElementObserver: message = "Invalid UI element observer"
    case .cannotComplete: message = "Cannot complete"
    case .attributeUnsupported: message = "Attribute unsupported"
    case .actionUnsupported: message = "Action unsupported"
    case .notificationUnsupported: message = "Notification unsupported"
    case .notImplemented: message = "Not implemented"
    case .notificationAlreadyRegistered: message = "Notification already registered"
    case .notificationNotRegistered: message = "Notification not registered"
    case .apiDisabled: message = "API disabled"
    case .noValue: message = "No value"
    case .parameterizedAttributeUnsupported: message = "Parameterized attribute unsupported"
    case .notEnoughPrecision: message = "Not enough precision"
    @unknown default: message = "Unknown error"
    }

    return "AXError: \(message) (\(self.rawValue))"
  }
}

extension AXError {
  func throwIfFailed() throws {
    if self != .success {
      throw self
    }
  }
}

extension CGError: @retroactive _BridgedNSError, @retroactive LocalizedError {
  public var errorDescription: String? {
    let message: String

    switch self {
    case .success: message = "Success"
    case .failure: message = "Failure"
    case .illegalArgument: message = "Illegal argument"
    case .invalidConnection: message = "Invalid connection"
    case .invalidContext: message = "Invalid context"
    case .cannotComplete: message = "Cannot complete"
    case .notImplemented: message = "Not implemented"
    case .rangeCheck: message = "Range check error"
    case .typeCheck: message = "Type check error"
    case .invalidOperation: message = "Invalid operation"
    case .noneAvailable: message = "Error code not available"
    @unknown default: message = "Unknown error"
    }

    return "CGError: \(message) (\(self.rawValue))"
  }
}

struct CPSSetFrontProcessOptions: OptionSet {
  let rawValue: UInt32

  static let allWindows = CPSSetFrontProcessOptions(rawValue: 0x100)
  static let userGenerated = CPSSetFrontProcessOptions(rawValue: 0x200)
  static let noWindows = CPSSetFrontProcessOptions(rawValue: 0x400)
}

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

  enum FocusTransitionType: UInt8 {
    case becomeKey = 0x01
    case resignKey = 0x02

    var eventType: EventType { .focusTransition }
  }

  var bytes: [UInt8]

  private init() {
    self.bytes = [UInt8](repeating: 0, count: Self.size)
    self.bytes[Offset.recordLength] = UInt8(Self.size)
  }

  static func focusTransition(windowID: CGWindowID, type: FocusTransitionType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = type.eventType.rawValue
    eventRecord.bytes[Offset.focusTransitionType] = type.rawValue
    eventRecord.setWindowID(windowID)

    return eventRecord
  }

  static func simulatedClick(windowID: CGWindowID, type: SimulatedClickType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = type.eventType.rawValue

    for index in 0..<0x10 {
      eventRecord.bytes[Offset.mask + index] = 0xff
    }

    eventRecord.bytes[Offset.activationFlag] = 0x10
    eventRecord.setWindowID(windowID)

    return eventRecord
  }

  private mutating func setWindowID(_ windowID: CGWindowID) {
    var windowID = windowID

    withUnsafeBytes(of: &windowID) { idBytes in
      for index in 0..<4 {
        self.bytes[Offset.windowID + index] = idBytes[index]
      }
    }
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

  private typealias SLSConnectionID = UInt32
  private typealias SLSMainConnectionID = @convention(c) () -> SLSConnectionID
  private typealias SLSFindWindowByGeometry =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ filterWindowID: CGWindowID,
      _ flags: Int32,
      _ reserved: Int32,
      _ screenPoint: UnsafePointer<CGPoint>,
      _ outWindowPoint: UnsafeMutablePointer<CGPoint>,
      _ outWindowID: UnsafeMutablePointer<CGWindowID>,
      _ outWindowConnectionID: UnsafeMutablePointer<SLSConnectionID>
    ) -> CGError
  private typealias SLSGetWindowLevel =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ windowID: CGWindowID,
      _ outLevel: UnsafeMutablePointer<CGWindowLevel>
    ) -> CGError
  private typealias SLSConnectionGetPID =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ outPID: UnsafeMutablePointer<pid_t>
    ) -> CGError
  private typealias SLSCopyAssociatedWindows =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ windowID: CGWindowID
    ) -> CFArray
  // swift-format-ignore: NoLeadingUnderscores
  private typealias _SLPSGetFrontProcess = @convention(c) (_ psn: UnsafeMutableRawPointer) -> CGError
  // swift-format-ignore: NoLeadingUnderscores
  private typealias _SLPSSetFrontProcessWithOptions =
    @convention(c) (
      _ psn: UnsafeMutableRawPointer,
      _ windowID: CGWindowID,
      _ options: CPSSetFrontProcessOptions.RawValue
    ) -> CGError
  private typealias SLPSPostEventRecordTo =
    @convention(c) (
      _ psn: UnsafeMutableRawPointer,
      _ bytes: UnsafeMutablePointer<UInt8>
    ) -> CGError

  private let mainConnectionID: UInt32
  private let slsFindWindowByGeometry: SLSFindWindowByGeometry
  private let slsGetWindowLevel: SLSGetWindowLevel
  private let slsConnectionGetPID: SLSConnectionGetPID
  private let slsCopyAssociatedWindows: SLSCopyAssociatedWindows
  // swift-format-ignore: NoLeadingUnderscores
  private let _slpsGetFrontProcess: _SLPSGetFrontProcess
  // swift-format-ignore: NoLeadingUnderscores
  private let _slpsSetFrontProcessWithOptions: _SLPSSetFrontProcessWithOptions
  private let slpsPostEventRecordTo: SLPSPostEventRecordTo

  var frontProcess: ProcessSerialNumber? {
    var processSerialNumber = ProcessSerialNumber()
    return _slpsGetFrontProcess(&processSerialNumber) == .success ? processSerialNumber : nil
  }

  init() throws {
    guard
      let skyLightHandle: UnsafeMutableRawPointer = dlopen(
        "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
        RTLD_LAZY
      )
    else {
      throw Error.frameworkNotFound
    }

    guard let slsMainConnectionIDSymbol = dlsym(skyLightHandle, "SLSMainConnectionID") else {
      throw Error.symbolNotFound("SLSMainConnectionID")
    }

    guard let slsFindWindowByGeometrySymbol = dlsym(skyLightHandle, "SLSFindWindowByGeometry") else {
      throw Error.symbolNotFound("SLSFindWindowByGeometry")
    }

    guard let slsGetWindowLevelSymbol = dlsym(skyLightHandle, "SLSGetWindowLevel") else {
      throw Error.symbolNotFound("SLSGetWindowLevel")
    }

    guard let slsConnectionGetPIDSymbol = dlsym(skyLightHandle, "SLSConnectionGetPID") else {
      throw Error.symbolNotFound("SLSConnectionGetPID")
    }

    guard let slsCopyAssociatedWindowsSymbol = dlsym(skyLightHandle, "SLSCopyAssociatedWindows") else {
      throw Error.symbolNotFound("SLSCopyAssociatedWindows")
    }

    // swift-format-ignore: NoLeadingUnderscores
    guard let _slpsGetFrontProcessSymbol = dlsym(skyLightHandle, "_SLPSGetFrontProcess") else {
      throw Error.symbolNotFound("_SLPSGetFrontProcess")
    }

    // swift-format-ignore: NoLeadingUnderscores
    guard let _slpsSetFrontProcessWithOptionsSymbol = dlsym(skyLightHandle, "_SLPSSetFrontProcessWithOptions") else {
      throw Error.symbolNotFound("_SLPSSetFrontProcessWithOptions")
    }

    guard let slpsPostEventRecordToSymbol = dlsym(skyLightHandle, "SLPSPostEventRecordTo") else {
      throw Error.symbolNotFound("SLPSPostEventRecordTo")
    }

    self.mainConnectionID = unsafeBitCast(slsMainConnectionIDSymbol, to: SLSMainConnectionID.self)()
    self.slsFindWindowByGeometry = unsafeBitCast(slsFindWindowByGeometrySymbol, to: SLSFindWindowByGeometry.self)
    self.slsGetWindowLevel = unsafeBitCast(slsGetWindowLevelSymbol, to: SLSGetWindowLevel.self)
    self.slsConnectionGetPID = unsafeBitCast(slsConnectionGetPIDSymbol, to: SLSConnectionGetPID.self)
    self.slsCopyAssociatedWindows = unsafeBitCast(slsCopyAssociatedWindowsSymbol, to: SLSCopyAssociatedWindows.self)
    self._slpsGetFrontProcess = unsafeBitCast(_slpsGetFrontProcessSymbol, to: _SLPSGetFrontProcess.self)
    self._slpsSetFrontProcessWithOptions = unsafeBitCast(
      _slpsSetFrontProcessWithOptionsSymbol,
      to: _SLPSSetFrontProcessWithOptions.self
    )
    self.slpsPostEventRecordTo = unsafeBitCast(slpsPostEventRecordToSymbol, to: SLPSPostEventRecordTo.self)
  }

  func findWindow(at point: CGPoint) -> (windowID: CGWindowID, ownerPID: pid_t)? {
    var screenPoint = point
    var windowPoint = CGPoint.zero
    var windowID: CGWindowID = 0
    var windowCID: SLSConnectionID = 0
    var ownerPID: pid_t = 0

    return
      slsFindWindowByGeometry(mainConnectionID, 0, 1, 0, &screenPoint, &windowPoint, &windowID, &windowCID) == .success
      && windowID != 0
      && slsConnectionGetPID(windowCID, &ownerPID) == .success
      ? (windowID, ownerPID)
      : nil
  }

  func windowLevel(for windowID: CGWindowID) -> CGWindowLevel? {
    var level: CGWindowLevel = 0
    return slsGetWindowLevel(mainConnectionID, windowID, &level) == .success ? level : nil
  }

  func associatedWindows(for windowID: CGWindowID) -> [CGWindowID] {
    guard let windowIDs = slsCopyAssociatedWindows(mainConnectionID, windowID) as? [CGWindowID] else {
      return []
    }

    return windowIDs.filter { $0 != windowID }
  }

  @discardableResult
  func setFrontProcess(
    _ processSerialNumber: ProcessSerialNumber,
    windowID: CGWindowID,
    options: CPSSetFrontProcessOptions
  ) -> CGError {
    var processSerialNumber = processSerialNumber
    return _slpsSetFrontProcessWithOptions(&processSerialNumber, windowID, options.rawValue)
  }

  @discardableResult
  func postEvent(_ eventRecord: SLPSEventRecord, to processSerialNumber: ProcessSerialNumber) -> CGError {
    var eventRecord = eventRecord
    var processSerialNumber = processSerialNumber

    return eventRecord.bytes.withUnsafeMutableBufferPointer { buffer in
      slpsPostEventRecordTo(&processSerialNumber, buffer.baseAddress!)
    }
  }
}

@MainActor
final class FocusManager {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionNotGranted
    case failedToCreateEventTap
    case failedToCreateRunLoopSource

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionNotGranted: "Accessibility permission not granted."
      case .failedToCreateEventTap: "Failed to create event tap."
      case .failedToCreateRunLoopSource: "Failed to create run loop source for event tap."
      }
    }
  }

  private(set) var isEnabled = true

  private let startDate = Date.now
  private let skyLightProxy: SkyLightProxy
  private let debounceTimer: any DispatchSourceTimer
  private let suspendingWindowLevels: Set<CGWindowLevel> = [
    CGWindowLevelForKey(.modalPanelWindow),
    CGWindowLevelForKey(.popUpMenuWindow),
    CGWindowLevelForKey(.screenSaverWindow),
    CGWindowLevelForKey(.overlayWindow)
  ]
  private let windowManagerSuspendingWindowLevels: Set<CGWindowLevel> = [18, 19]
  private let hoverDelay: DispatchTimeInterval
  private let jitterThresholdSquared: CGFloat
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var spaceObservationTask: Task<Void, Never>?
  private var lastMouseLocation: CGPoint = .zero
  private var lastMouseMoveTime: DispatchTime = .now()
  private var isCommandKeyPressed = false
  private var isFocusPending = false
  private var focusTask: Task<Void, Never>?

  init(hoverDelay: DispatchTimeInterval, jitterThreshold: Int) throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    AXUIElement.setGlobalMessagingTimeout(seconds: 0.5)

    self.hoverDelay = hoverDelay
    self.jitterThresholdSquared = CGFloat(jitterThreshold * jitterThreshold)
    self.skyLightProxy = try SkyLightProxy()
    self.debounceTimer = DispatchSource.makeTimerSource(queue: .main)

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: CGEventMask(
          [
            CGEventType.mouseMoved,
            CGEventType.leftMouseDragged,
            CGEventType.rightMouseDragged,
            CGEventType.flagsChanged
          ].reduce(0) { $0 | (1 << $1.rawValue) }
        ),
        callback: { _, _, event, refcon in
          if let refcon {
            MainActor.assumeIsolated {
              Unmanaged<FocusManager>.fromOpaque(refcon).takeUnretainedValue().handleCGEvent(event)
            }
          }

          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
      CFMachPortInvalidate(eventTap)
      throw Error.failedToCreateRunLoopSource
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    let spaceObservationTask = Task { [weak self] in
      for await _ in NSWorkspace.shared.notificationCenter.notifications(
        named: NSWorkspace.activeSpaceDidChangeNotification
      ) {
        guard let self else {
          break
        }

        cancelPendingFocus()
      }
    }

    debounceTimer.setEventHandler { [weak self] in
      self?.handleTimerEvent()
    }

    debounceTimer.resume()

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
    self.spaceObservationTask = spaceObservationTask
  }

  isolated deinit {
    if let eventTap, let runLoopSource {
      if CGEvent.tapIsEnabled(tap: eventTap) {
        CGEvent.tapEnable(tap: eventTap, enable: false)
      }

      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFMachPortInvalidate(eventTap)
    }

    spaceObservationTask?.cancel()
    debounceTimer.cancel()
    focusTask?.cancel()
  }

  func toggleEnabled() {
    self.isEnabled.toggle()
    updateEventTapState()
  }

  func logDiagnosticReport() {
    let isScreenLocked = isScreenLocked()
    let suspendingWindows = suspendingWindowsOnScreen().map { windowInfo in
      let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID ?? kCGNullWindowID
      let ownerName = windowInfo[kCGWindowOwnerName as String] as? String ?? "<unknown>"

      return "\(windowID) (\(ownerName))"
    }

    Log.message(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Enabled: \(isEnabled)
        Event tap enabled: \(eventTap.map { "\(CGEvent.tapIsEnabled(tap: $0))" } ?? "<none>")
        Suspended: \(isCommandKeyPressed || isScreenLocked || !suspendingWindows.isEmpty)
          Command key pressed: \(isCommandKeyPressed)
          Screen locked: \(isScreenLocked)
          Suspending windows on screen: \(suspendingWindows.isEmpty ? "none" : suspendingWindows.joined(separator: ", "))
        Focus pending: \(isFocusPending)
        Hover delay: \(hoverDelay)
      """
    )
  }

  private func updateEventTapState() {
    guard let eventTap, CGEvent.tapIsEnabled(tap: eventTap) != isEnabled else {
      return
    }

    CGEvent.tapEnable(tap: eventTap, enable: isEnabled)
    self.isCommandKeyPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
  }

  private func handleCGEvent(_ event: CGEvent) {
    switch event.type {
    case .mouseMoved:
      guard isEnabled, !isCommandKeyPressed else {
        break
      }

      let deltaX = event.location.x - lastMouseLocation.x
      let deltaY = event.location.y - lastMouseLocation.y

      guard (deltaX * deltaX) + (deltaY * deltaY) > jitterThresholdSquared else {
        break
      }

      self.lastMouseLocation = event.location
      self.lastMouseMoveTime = .now()

      if !isFocusPending {
        self.isFocusPending = true
        debounceTimer.schedule(deadline: lastMouseMoveTime + hoverDelay)
      }

    case .leftMouseDragged, .rightMouseDragged:
      cancelPendingFocus()

    case .flagsChanged:
      self.isCommandKeyPressed = event.flags.contains(.maskCommand)

      if isCommandKeyPressed {
        cancelPendingFocus()
      }

    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let eventTap, isEnabled {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }

      self.isCommandKeyPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)

    default:
      break
    }
  }

  private func handleTimerEvent() {
    guard isFocusPending else {
      return
    }

    guard isEnabled, !isCommandKeyPressed else {
      cancelPendingFocus()
      return
    }

    let focusDeadline = lastMouseMoveTime + hoverDelay

    guard DispatchTime.now() >= focusDeadline else {
      debounceTimer.schedule(deadline: focusDeadline)
      return
    }

    focusTask?.cancel()

    self.isFocusPending = false
    self.focusTask = Task { [weak self, lastMouseLocation] in
      await self?.focusWindow(at: lastMouseLocation)
    }
  }

  private nonisolated func focusWindow(at point: CGPoint) async {
    var targetPSN = ProcessSerialNumber()

    guard
      let (targetWindowID, targetPID) = skyLightProxy.findWindow(at: point),
      skyLightProxy.windowLevel(for: targetWindowID) == kCGNormalWindowLevel,
      GetProcessForPID(targetPID, &targetPSN) == noErr
    else {
      return
    }

    var focusedWindow: (windowID: CGWindowID, processSerialNumber: ProcessSerialNumber)?
    var isSameProcess: DarwinBoolean = false

    if var focusedPSN = skyLightProxy.frontProcess,
      SameProcess(&targetPSN, &focusedPSN, &isSameProcess) == noErr,
      isSameProcess.boolValue
    {
      let focusedWindowID: CGWindowID?

      do {
        focusedWindowID = try AXUIElementCreateApplication(targetPID)
          .value(for: .focusedWindow, as: AXUIElement.self)
          .windowID()

      } catch AXError.noValue {
        focusedWindowID = nil

      } catch {
        focusedWindowID = nil
        Log.error("Failed to retrieve focused window for PID \(targetPID): \(error.localizedDescription)")
      }

      if let focusedWindowID {
        guard
          focusedWindowID != targetWindowID,
          !skyLightProxy.associatedWindows(for: focusedWindowID).contains(targetWindowID)
        else {
          return
        }

        focusedWindow = (focusedWindowID, focusedPSN)
      }
    }

    guard
      !Task.isCancelled,
      NSRunningApplication(processIdentifier: targetPID)?.isSystemAgent != true,
      !isScreenLocked(),
      suspendingWindowsOnScreen().isEmpty,
      !Task.isCancelled
    else {
      return
    }

    if let focusedWindow,
      skyLightProxy.postEvent(
        .focusTransition(windowID: focusedWindow.windowID, type: .resignKey),
        to: focusedWindow.processSerialNumber
      ) == .success
    {
      await withTaskCancellationShield {
        try? await Task.sleep(for: .milliseconds(10))
      }

      skyLightProxy.postEvent(.focusTransition(windowID: targetWindowID, type: .becomeKey), to: targetPSN)
    }

    guard
      skyLightProxy.setFrontProcess(targetPSN, windowID: targetWindowID, options: .userGenerated) == .success,
      skyLightProxy.postEvent(
        .simulatedClick(windowID: targetWindowID, type: .leftMouseDown),
        to: targetPSN
      ) == .success
    else {
      return
    }

    skyLightProxy.postEvent(.simulatedClick(windowID: targetWindowID, type: .leftMouseUp), to: targetPSN)
  }

  private func cancelPendingFocus() {
    focusTask?.cancel()

    self.isFocusPending = false
    self.focusTask = nil
  }

  private nonisolated func isScreenLocked() -> Bool {
    return (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] != nil
  }

  private nonisolated func suspendingWindowsOnScreen() -> [[String: Any]] {
    let windowsInfo =
      CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]] ?? []
    return windowsInfo.filter { isSuspendingWindow(info: $0) }
  }

  private nonisolated func isSuspendingWindow(info windowInfo: [String: Any]) -> Bool {
    guard let windowLevel = windowInfo[kCGWindowLayer as String] as? CGWindowLevel else {
      return false
    }

    if windowManagerSuspendingWindowLevels.contains(windowLevel) {
      guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
        return false
      }

      return NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier == "com.apple.WindowManager"
    }

    return suspendingWindowLevels.contains(windowLevel) && windowInfo[kCGWindowAlpha as String] as? Double ?? 1 > 0
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var singleInstanceLock: SingleInstanceLock?
  private var focusManager: FocusManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.focusManager = try FocusManager(
        hoverDelay: Configuration.hoverDelay,
        jitterThreshold: Configuration.jitterThreshold
      )
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }

    observeProcessSignals()
    observeIPCCommands()
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.singleInstanceLock = nil
    self.focusManager = nil
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
    case .toggle: focusManager?.toggleEnabled()
    case .printLog: focusManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, CaseIterable {
  case toggle
  case printLog = "print-log"
  case quit

  static let notificationName = Notification.Name("\(Configuration.subsystem).IPCCommand")
  static let notificationUserInfoKey = "command"

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
