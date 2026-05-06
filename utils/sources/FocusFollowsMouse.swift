import AppKit

enum Constants {
  static let subsystem = "industries.britown.FocusFollowsMouse"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let hoverDelay: DispatchTimeInterval = .milliseconds(150)
  static let jitterThresholdSquared: CGFloat = 3 * 3
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
      sources.forEach { source in
        source.cancel()
      }
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
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

extension AXUIElement {
  var windowID: CGWindowID? {
    var windowID: CGWindowID = kCGNullWindowID
    return _AXUIElementGetWindow(self, &windowID) == .success ? windowID : nil
  }

  func value<T>(for attribute: NSAccessibility.Attribute, as type: T.Type = T.self) -> T? {
    var rawValue: CFTypeRef?
    return AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &rawValue) == .success
      ? rawValue as? T
      : nil
  }
}

extension NSAccessibility.Notification {
  static let exposeShowAllWindows = Self(rawValue: "AXExposeShowAllWindows")
  static let exposeShowFrontWindows = Self(rawValue: "AXExposeShowFrontWindows")
  static let exposeShowDesktop = Self(rawValue: "AXExposeShowDesktop")
  static let exposeExit = Self(rawValue: "AXExposeExit")
}

enum CGSEventType: UInt32 {
  case spaceWindowCreated = 1325
  case spaceWindowDestroyed = 1326
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

  static func focusTransition(windowID: CGWindowID, type focusTransitionType: FocusTransitionType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = focusTransitionType.eventType.rawValue
    eventRecord.bytes[Offset.focusTransitionType] = focusTransitionType.rawValue
    eventRecord.setWindowID(windowID)

    return eventRecord
  }

  static func simulatedClick(windowID: CGWindowID, type simulatedClickType: SimulatedClickType) -> SLPSEventRecord {
    var eventRecord = SLPSEventRecord()
    eventRecord.bytes[Offset.eventType] = simulatedClickType.eventType.rawValue

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

  typealias SLSNotifyProc =
    @convention(c) (
      _ eventType: CGSEventType.RawValue,
      _ data: UnsafeMutableRawPointer?,
      _ dataLength: UInt32,
      _ context: UnsafeMutableRawPointer?
    ) -> Void

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
  private typealias SLSRegisterNotifyProc =
    @convention(c) (
      _ proc: SLSNotifyProc,
      _ eventType: CGSEventType.RawValue,
      _ context: UnsafeMutableRawPointer?
    ) -> CGError
  private typealias SLSRemoveNotifyProc =
    @convention(c) (
      _ proc: SLSNotifyProc,
      _ eventType: CGSEventType.RawValue,
      _ context: UnsafeMutableRawPointer?
    ) -> CGError
  private typealias _SLPSGetFrontProcess = @convention(c) (_ psn: UnsafeMutableRawPointer) -> CGError
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
  private let slsRegisterNotifyProc: SLSRegisterNotifyProc
  private let slsRemoveNotifyProc: SLSRemoveNotifyProc
  private let _slpsGetFrontProcess: _SLPSGetFrontProcess
  private let _slpsSetFrontProcessWithOptions: _SLPSSetFrontProcessWithOptions
  private let slpsPostEventRecordTo: SLPSPostEventRecordTo

  var frontProcess: ProcessSerialNumber? {
    var processSerialNumber = ProcessSerialNumber()
    return _slpsGetFrontProcess(&processSerialNumber) == .success ? processSerialNumber : nil
  }

  init() throws {
    guard let skyLightHandle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW) else {
      throw Error.frameworkNotFound
    }

    guard let slsMainConnectionIDSymbol = dlsym(skyLightHandle, "SLSMainConnectionID") else {
      throw Error.symbolNotFound("SLSMainConnectionID")
    }

    guard let slsFindWindowByGeometrySymbol = dlsym(skyLightHandle, "SLSFindWindowByGeometry") else {
      throw Error.symbolNotFound("SLSFindWindowByGeometry")
    }

    guard let slsRegisterNotifyProcSymbol = dlsym(skyLightHandle, "SLSRegisterNotifyProc") else {
      throw Error.symbolNotFound("SLSRegisterNotifyProc")
    }

    guard let slsRemoveNotifyProcSymbol = dlsym(skyLightHandle, "SLSRemoveNotifyProc") else {
      throw Error.symbolNotFound("SLSRemoveNotifyProc")
    }

    guard let _slpsGetFrontProcessSymbol = dlsym(skyLightHandle, "_SLPSGetFrontProcess") else {
      throw Error.symbolNotFound("_SLPSGetFrontProcess")
    }

    guard let _slpsSetFrontProcessWithOptionsSymbol = dlsym(skyLightHandle, "_SLPSSetFrontProcessWithOptions") else {
      throw Error.symbolNotFound("_SLPSSetFrontProcessWithOptions")
    }

    guard let slpsPostEventRecordToSymbol = dlsym(skyLightHandle, "SLPSPostEventRecordTo") else {
      throw Error.symbolNotFound("SLPSPostEventRecordTo")
    }

    self.mainConnectionID = unsafeBitCast(slsMainConnectionIDSymbol, to: SLSMainConnectionID.self)()
    self.slsFindWindowByGeometry = unsafeBitCast(slsFindWindowByGeometrySymbol, to: SLSFindWindowByGeometry.self)
    self.slsRegisterNotifyProc = unsafeBitCast(slsRegisterNotifyProcSymbol, to: SLSRegisterNotifyProc.self)
    self.slsRemoveNotifyProc = unsafeBitCast(slsRemoveNotifyProcSymbol, to: SLSRemoveNotifyProc.self)
    self._slpsGetFrontProcess = unsafeBitCast(_slpsGetFrontProcessSymbol, to: _SLPSGetFrontProcess.self)
    self._slpsSetFrontProcessWithOptions = unsafeBitCast(
      _slpsSetFrontProcessWithOptionsSymbol,
      to: _SLPSSetFrontProcessWithOptions.self
    )
    self.slpsPostEventRecordTo = unsafeBitCast(slpsPostEventRecordToSymbol, to: SLPSPostEventRecordTo.self)
  }

  func findWindow(at point: CGPoint) -> CGWindowID? {
    var screenPoint = point
    var windowPoint = CGPoint.zero
    var windowID: CGWindowID = 0
    var windowCID: UInt32 = 0

    return
      slsFindWindowByGeometry(mainConnectionID, 0, 1, 0, &screenPoint, &windowPoint, &windowID, &windowCID) == .success
      && windowID != 0
      ? windowID
      : nil
  }

  @discardableResult
  func registerNotificationCallback(
    _ callback: SLSNotifyProc,
    for eventType: CGSEventType,
    context: UnsafeMutableRawPointer?,
  ) -> CGError {
    return slsRegisterNotifyProc(callback, eventType.rawValue, context)
  }

  @discardableResult
  func removeNotificationCallback(
    _ callback: SLSNotifyProc,
    for eventType: CGSEventType,
    context: UnsafeMutableRawPointer?,
  ) -> CGError {
    return slsRemoveNotifyProc(callback, eventType.rawValue, context)
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
final class WindowMonitor {
  enum Error: Swift.Error, LocalizedError {
    case failedToRegisterForNotifications(eventType: CGSEventType, code: CGError)

    var errorDescription: String? {
      switch self {
      case .failedToRegisterForNotifications(let eventType, let code):
        "Failed to register for \(eventType) notifications (\(code))."
      }
    }
  }

  enum Event {
    case windowAdded(windowID: CGWindowID)
    case windowRemoved(windowID: CGWindowID)
  }

  private let skyLightProxy: SkyLightProxy

  private let slsNotifyProc: SkyLightProxy.SLSNotifyProc = { eventType, data, dataLength, context in
    guard let event = CGSEventType(rawValue: eventType), let context else {
      return
    }

    Unmanaged<WindowMonitor>.fromOpaque(context).takeUnretainedValue().handleEvent(
      event,
      data: data,
      dataLength: dataLength
    )
  }

  private var registeredEventTypes: [CGSEventType] = []
  private var continuation: AsyncStream<Event>.Continuation?

  init(skyLightProxy: SkyLightProxy) throws {
    self.skyLightProxy = skyLightProxy

    for eventType: CGSEventType in [.spaceWindowCreated, .spaceWindowDestroyed] {
      let error = skyLightProxy.registerNotificationCallback(
        slsNotifyProc,
        for: eventType,
        context: Unmanaged.passUnretained(self).toOpaque()
      )

      guard error == .success else {
        unregisterNotifyProc()
        throw Error.failedToRegisterForNotifications(eventType: eventType, code: error)
      }

      self.registeredEventTypes.append(eventType)
    }
  }

  isolated deinit {
    continuation?.finish()
    unregisterNotifyProc()
  }

  func events() -> AsyncStream<Event> {
    continuation?.finish()

    let (stream, continuation) = AsyncStream.makeStream(of: Event.self)

    self.continuation = continuation

    return stream
  }

  private func handleEvent(_ event: CGSEventType, data: UnsafeMutableRawPointer?, dataLength: UInt32) {
    guard let continuation, let data, dataLength >= 12 else {
      return
    }

    let windowID = data.advanced(by: 8).load(as: CGWindowID.self)

    switch event {
    case .spaceWindowCreated: continuation.yield(.windowAdded(windowID: windowID))
    case .spaceWindowDestroyed: continuation.yield(.windowRemoved(windowID: windowID))
    }
  }

  private func unregisterNotifyProc() {
    for eventType in registeredEventTypes {
      skyLightProxy.removeNotificationCallback(
        slsNotifyProc,
        for: eventType,
        context: Unmanaged.passUnretained(self).toOpaque()
      )
    }

    self.registeredEventTypes.removeAll()
    self.continuation = nil
  }
}

@MainActor
final class MissionControlMonitor {
  enum Error: Swift.Error, LocalizedError {
    case accessibilityPermissionDenied
    case failedToFindDockProcess
    case failedToCreateObserver
    case failedToAddNotification(notification: NSAccessibility.Notification, code: AXError)

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionDenied:
        "Accessibility permission denied."

      case .failedToFindDockProcess:
        "Failed to find Dock process."

      case .failedToCreateObserver:
        "Failed to create observer for Dock process."

      case .failedToAddNotification(let notification, let code):
        "Failed to observe \(notification) notifications (\(code.rawValue))."
      }
    }
  }

  enum Event {
    case activated
    case deactivated
  }

  private var dockElement: AXUIElement?
  private var axObserver: AXObserver?
  private var observedNotifications = Set<NSAccessibility.Notification>()
  private var runLoopSource: CFRunLoopSource?
  private var dockRestartObservationTask: Task<Void, Never>?
  private var continuation: AsyncStream<Event>.Continuation?

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }

    try startAXObserver()

    let dockRestartObservationTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: Notification.Name("NSApplicationDockDidRestartNotification")
      ) {
        try? self?.startAXObserver()
      }
    }

    self.dockRestartObservationTask = dockRestartObservationTask
  }

  isolated deinit {
    dockRestartObservationTask?.cancel()
    continuation?.finish()
    stopAXObserverIfNeeded()
  }

  func events() -> AsyncStream<Event> {
    continuation?.finish()

    let (stream, continuation) = AsyncStream.makeStream(of: Event.self)

    self.continuation = continuation

    return stream
  }

  private func startAXObserver() throws {
    stopAXObserverIfNeeded()

    guard
      let dockPID =
        NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.dock")
        .first?
        .processIdentifier
    else {
      throw Error.failedToFindDockProcess
    }

    let dockElement = AXUIElementCreateApplication(dockPID)
    let callback: AXObserverCallback = { _, _, notification, refcon in
      guard let refcon else {
        return
      }

      Unmanaged<MissionControlMonitor>.fromOpaque(refcon).takeUnretainedValue().handleAXNotification(
        NSAccessibility.Notification(rawValue: notification as String)
      )
    }

    var axObserver: AXObserver?

    guard AXObserverCreate(dockPID, callback, &axObserver) == .success, let axObserver else {
      throw Error.failedToCreateObserver
    }

    let selfPointer = Unmanaged.passUnretained(self).toOpaque()

    for notification: NSAccessibility.Notification in [
      .exposeShowAllWindows,
      .exposeShowFrontWindows,
      .exposeShowDesktop,
      .exposeExit
    ] {
      let error = AXObserverAddNotification(axObserver, dockElement, notification as CFString, selfPointer)

      guard error == .success else {
        stopAXObserverIfNeeded()
        throw Error.failedToAddNotification(notification: notification, code: error)
      }

      self.observedNotifications.insert(notification)
    }

    let runLoopSource = AXObserverGetRunLoopSource(axObserver)

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

    self.axObserver = axObserver
    self.dockElement = dockElement
    self.runLoopSource = runLoopSource
  }

  private func stopAXObserverIfNeeded() {
    if let axObserver, let dockElement {
      observedNotifications.forEach { notification in
        AXObserverRemoveNotification(axObserver, dockElement, notification as CFString)
      }
    }

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    self.axObserver = nil
    self.dockElement = nil
    self.observedNotifications.removeAll()
    self.runLoopSource = nil
  }

  private func handleAXNotification(_ notification: NSAccessibility.Notification) {
    guard let continuation else {
      return
    }

    switch notification {
    case .exposeShowAllWindows, .exposeShowFrontWindows, .exposeShowDesktop: continuation.yield(.activated)
    case .exposeExit: continuation.yield(.deactivated)
    default: break
    }
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

  private(set) var isEnabled = true

  private let skyLightProxy: SkyLightProxy
  private let windowMonitor: WindowMonitor
  private let missionControlMonitor: MissionControlMonitor
  private let debounceTimer: DispatchSourceTimer
  private var cgEventTap: CFMachPort?
  private var cgEventRunLoopSource: CFRunLoopSource?
  private var observationTask: Task<Void, Never>?
  private var lastMouseLocation: CGPoint = .zero
  private var lastMouseMoveTime: DispatchTime = .now()
  private var isLeftMouseDown = false
  private var isCommandKeyPressed = false
  private var modalWindows: [CGWindowID: Int] = [:]
  private var isMissionControlActive = false
  private var isSystemSleeping = false
  private var isFocusPending = false
  private var focusTask: Task<Void, Never>?

  private var isSuspended: Bool {
    isLeftMouseDown || isCommandKeyPressed || !modalWindows.isEmpty || isMissionControlActive || isSystemSleeping
  }

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionDenied
    }

    self.skyLightProxy = try SkyLightProxy()
    self.windowMonitor = try WindowMonitor(skyLightProxy: skyLightProxy)
    self.missionControlMonitor = try MissionControlMonitor()
    self.debounceTimer = DispatchSource.makeTimerSource(queue: .main)

    guard
      let cgEventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: 1 << CGEventType.mouseMoved.rawValue
          | 1 << CGEventType.leftMouseDown.rawValue
          | 1 << CGEventType.leftMouseUp.rawValue
          | 1 << CGEventType.otherMouseDown.rawValue
          | 1 << CGEventType.rightMouseDown.rawValue
          | 1 << CGEventType.flagsChanged.rawValue,
        callback: { _, _, event, refcon in
          if let refcon {
            Unmanaged<FocusManager>.fromOpaque(refcon).takeUnretainedValue().handleCGEvent(event)
          }

          return Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    let cgEventRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, cgEventTap, 0)

    CFRunLoopAddSource(CFRunLoopGetMain(), cgEventRunLoopSource, .commonModes)
    CGEvent.tapEnable(tap: cgEventTap, enable: true)

    let observationTask = Task { [weak self] in
      await withDiscardingTaskGroup { group in
        group.addTask { await self?.monitorWindows() }
        group.addTask { await self?.monitorMissionControlState() }
      }
    }

    debounceTimer.setEventHandler { [weak self] in
      self?.handleTimerEvent()
    }

    debounceTimer.resume()

    self.cgEventTap = cgEventTap
    self.cgEventRunLoopSource = cgEventRunLoopSource
    self.observationTask = observationTask
  }

  deinit {
    debounceTimer.cancel()
    observationTask?.cancel()
    focusTask?.cancel()

    if let cgEventTap {
      CGEvent.tapEnable(tap: cgEventTap, enable: false)
      CFMachPortInvalidate(cgEventTap)
    }

    if let cgEventRunLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), cgEventRunLoopSource, .commonModes)
    }
  }

  func toggleEnabled() {
    guard let cgEventTap else {
      return
    }

    self.isEnabled.toggle()

    CGEvent.tapEnable(tap: cgEventTap, enable: isEnabled)
  }

  private func monitorWindows() async {
    for await event in windowMonitor.events() {
      handleWindowEvent(event)
    }
  }

  private func monitorMissionControlState() async {
    for await event in missionControlMonitor.events() {
      handleMissionControlStateChange(event)
    }
  }

  private func handleCGEvent(_ event: CGEvent) {
    switch event.type {
    case .mouseMoved:
      guard isEnabled, !isSuspended else {
        break
      }

      let deltaX = event.location.x - lastMouseLocation.x
      let deltaY = event.location.y - lastMouseLocation.y

      guard (deltaX * deltaX) + (deltaY * deltaY) > Constants.jitterThresholdSquared else {
        break
      }

      self.lastMouseLocation = event.location
      self.lastMouseMoveTime = .now()

      if !isFocusPending {
        self.isFocusPending = true
        debounceTimer.schedule(deadline: lastMouseMoveTime + Constants.hoverDelay)
      }

    case .leftMouseDown, .otherMouseDown, .rightMouseDown:
      if event.type == .leftMouseDown {
        self.isLeftMouseDown = true
      }

      cancelPendingFocus()

    case .leftMouseUp:
      self.isLeftMouseDown = false

    case .flagsChanged:
      self.isCommandKeyPressed = event.flags.contains(.maskCommand)

      if isCommandKeyPressed {
        cancelPendingFocus()
      }

    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if isEnabled, let cgEventTap {
        CGEvent.tapEnable(tap: cgEventTap, enable: true)
      }

    default:
      break
    }
  }

  private func handleWindowEvent(_ event: WindowMonitor.Event) {
    switch event {
    case .windowAdded(let windowID):
      if let currentCount = modalWindows[windowID] {
        modalWindows[windowID] = currentCount + 1
        return
      }

      if let windowsInfo = CGWindowListCopyWindowInfo(
        [.optionIncludingWindow, .excludeDesktopElements],
        windowID
      ) as? [[String: Any]],
        let windowInfo = windowsInfo.first,
        let windowLayer = windowInfo[kCGWindowLayer as String] as? CGWindowLevel,
        windowLayer > kCGNormalWindowLevel,
        windowLayer <= kCGScreenSaverWindowLevel,
        windowLayer != kCGFloatingWindowLevel,
        windowInfo[kCGWindowAlpha as String] as? CGFloat ?? 1.0 == 1.0
      {
        modalWindows[windowID] = 1
      }

    case .windowRemoved(let windowID):
      guard let currentCount = modalWindows[windowID] else {
        return
      }

      if currentCount > 1 {
        modalWindows[windowID] = currentCount - 1
      } else {
        modalWindows.removeValue(forKey: windowID)
      }
    }
  }

  private func handleMissionControlStateChange(_ event: MissionControlMonitor.Event) {
    switch event {
    case .activated:
      self.isMissionControlActive = true
      cancelPendingFocus()

    case .deactivated:
      self.isMissionControlActive = false
    }
  }

  private func handleTimerEvent() {
    guard isFocusPending, isEnabled, !isSuspended else {
      cancelPendingFocus()
      return
    }

    let focusDeadline = lastMouseMoveTime + Constants.hoverDelay

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

  @concurrent
  private func focusWindow(at point: CGPoint) async {
    guard
      let targetWindowID = skyLightProxy.findWindow(at: point),
      let windowsInfo = CGWindowListCopyWindowInfo(
        [.optionIncludingWindow, .excludeDesktopElements],
        targetWindowID
      ) as? [[String: Any]],
      let windowInfo = windowsInfo.first,
      let targetPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
      windowInfo[kCGWindowLayer as String] as? CGWindowLevel == kCGNormalWindowLevel,
      !Task.isCancelled
    else {
      return
    }

    var targetPSN = ProcessSerialNumber()
    var isSameProcess: DarwinBoolean = false

    if GetProcessForPID(targetPID, &targetPSN) == noErr,
      var focusedPSN = skyLightProxy.frontProcess,
      SameProcess(&targetPSN, &focusedPSN, &isSameProcess) == noErr,
      isSameProcess.boolValue,
      let focusedWindowID = AXUIElementCreateApplication(targetPID)
        .value(for: .focusedWindow, as: AXUIElement.self)?
        .windowID
    {
      guard focusedWindowID != targetWindowID, !Task.isCancelled else {
        return
      }

      if skyLightProxy.postEvent(
        .focusTransition(windowID: focusedWindowID, type: .resignKey),
        to: focusedPSN
      ) == .success {
        try? await Task.sleep(for: .milliseconds(10))

        guard !Task.isCancelled else {
          return
        }

        skyLightProxy.postEvent(.focusTransition(windowID: targetWindowID, type: .becomeKey), to: targetPSN)
      }
    }

    guard
      !Task.isCancelled,
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
