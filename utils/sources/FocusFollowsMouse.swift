import AppKit

enum Configuration {
  static let subsystem = "industries.britown.FocusFollowsMouse"
  static let hoverDelay: DispatchTimeInterval = .milliseconds(150)
  static let jitterThresholdSquared: CGFloat = 3 * 3
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

typealias SpaceID = UInt64

enum CGSEventType: UInt32 {
  case packagesStatusBarSpaceChanged = 1308
  case spaceWindowCreated = 1325
  case spaceWindowDestroyed = 1326
  case spaceCurrentChanged = 1329
}

typealias SLSNotifyProc =
  @convention(c) (
    _ eventType: CGSEventType.RawValue,
    _ data: UnsafeMutableRawPointer?,
    _ dataLength: UInt32,
    _ context: UnsafeMutableRawPointer?
  ) -> Void

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
  private typealias SLSGetActiveSpace = @convention(c) (_ connectionID: SLSConnectionID) -> SpaceID
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
  private typealias SLSCopyAssociatedWindows =
    @convention(c) (
      _ connectionID: SLSConnectionID,
      _ windowID: CGWindowID
    ) -> CFArray
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
  private let slsGetActiveSpace: SLSGetActiveSpace
  private let slsFindWindowByGeometry: SLSFindWindowByGeometry
  private let slsCopyAssociatedWindows: SLSCopyAssociatedWindows
  private let slsRegisterNotifyProc: SLSRegisterNotifyProc
  private let slsRemoveNotifyProc: SLSRemoveNotifyProc
  private let _slpsGetFrontProcess: _SLPSGetFrontProcess
  private let _slpsSetFrontProcessWithOptions: _SLPSSetFrontProcessWithOptions
  private let slpsPostEventRecordTo: SLPSPostEventRecordTo

  var activeSpaceID: SpaceID { slsGetActiveSpace(mainConnectionID) }

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

    guard let slsGetActiveSpaceSymbol = dlsym(skyLightHandle, "SLSGetActiveSpace") else {
      throw Error.symbolNotFound("SLSGetActiveSpace")
    }

    guard let slsFindWindowByGeometrySymbol = dlsym(skyLightHandle, "SLSFindWindowByGeometry") else {
      throw Error.symbolNotFound("SLSFindWindowByGeometry")
    }

    guard let slsCopyAssociatedWindowsSymbol = dlsym(skyLightHandle, "SLSCopyAssociatedWindows") else {
      throw Error.symbolNotFound("SLSCopyAssociatedWindows")
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
    self.slsGetActiveSpace = unsafeBitCast(slsGetActiveSpaceSymbol, to: SLSGetActiveSpace.self)
    self.slsFindWindowByGeometry = unsafeBitCast(slsFindWindowByGeometrySymbol, to: SLSFindWindowByGeometry.self)
    self.slsCopyAssociatedWindows = unsafeBitCast(slsCopyAssociatedWindowsSymbol, to: SLSCopyAssociatedWindows.self)
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

  func associatedWindows(for windowID: CGWindowID) -> [CGWindowID] {
    guard let windowIDs = slsCopyAssociatedWindows(mainConnectionID, windowID) as? [CGWindowID] else {
      return []
    }

    return windowIDs.filter { $0 != windowID }
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
final class WorkspaceMonitor {
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
    case mainScreenChanged
    case currentSpaceChanged
    case windowAdded(windowID: CGWindowID, spaceID: SpaceID)
    case windowRemoved(windowID: CGWindowID, spaceID: SpaceID)
  }

  private let skyLightProxy: SkyLightProxy

  private let slsNotifyProc: SLSNotifyProc = { eventType, data, dataLength, context in
    guard let event = CGSEventType(rawValue: eventType), let context else {
      return
    }

    Unmanaged<WorkspaceMonitor>.fromOpaque(context).takeUnretainedValue().handleEvent(
      event,
      data: data,
      dataLength: dataLength
    )
  }

  private var registeredEventTypes: [CGSEventType] = []
  private var continuation: AsyncStream<Event>.Continuation?

  init(skyLightProxy: SkyLightProxy) throws {
    self.skyLightProxy = skyLightProxy

    for eventType: CGSEventType in [
      .packagesStatusBarSpaceChanged,
      .spaceWindowCreated,
      .spaceWindowDestroyed,
      .spaceCurrentChanged
    ] {
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
    guard let continuation else {
      return
    }

    switch event {
    case .packagesStatusBarSpaceChanged:
      continuation.yield(.mainScreenChanged)

    case .spaceWindowCreated:
      guard let data, dataLength >= MemoryLayout<SpaceID>.size + MemoryLayout<CGWindowID>.size else {
        return
      }

      let spaceID = data.load(as: SpaceID.self)
      let windowID = data.load(fromByteOffset: MemoryLayout<SpaceID>.size, as: CGWindowID.self)

      continuation.yield(.windowAdded(windowID: windowID, spaceID: spaceID))

    case .spaceWindowDestroyed:
      guard let data, dataLength >= MemoryLayout<SpaceID>.size + MemoryLayout<CGWindowID>.size else {
        return
      }

      let spaceID = data.load(as: SpaceID.self)
      let windowID = data.load(fromByteOffset: MemoryLayout<SpaceID>.size, as: CGWindowID.self)

      continuation.yield(.windowRemoved(windowID: windowID, spaceID: spaceID))

    case .spaceCurrentChanged:
      guard let data, dataLength >= MemoryLayout<SpaceID>.size + MemoryLayout<UInt8>.size else {
        return
      }

      let isCurrentFlag = data.load(fromByteOffset: MemoryLayout<SpaceID>.size, as: UInt8.self)

      guard isCurrentFlag != 0 else {
        return
      }

      continuation.yield(.currentSpaceChanged)
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
    case accessibilityPermissionNotGranted
    case failedToFindDockProcess
    case failedToCreateObserver
    case failedToAddNotification(notification: NSAccessibility.Notification, code: AXError)

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionNotGranted:
        "Accessibility permission not granted."

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
      throw Error.accessibilityPermissionNotGranted
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
    case accessibilityPermissionNotGranted
    case failedToCreateEventTap

    var errorDescription: String? {
      switch self {
      case .accessibilityPermissionNotGranted: return "Accessibility permission not granted."
      case .failedToCreateEventTap: return "Failed to create event tap."
      }
    }
  }

  private(set) var isEnabled = true

  private let skyLightProxy: SkyLightProxy
  private let workspaceMonitor: WorkspaceMonitor
  private let missionControlMonitor: MissionControlMonitor
  private let debounceTimer: DispatchSourceTimer
  private var cgEventTap: CFMachPort?
  private var cgEventRunLoopSource: CFRunLoopSource?
  private var observationTask: Task<Void, Never>?
  private var lastMouseLocation: CGPoint = .zero
  private var lastMouseMoveTime: DispatchTime = .now()
  private var isCommandKeyPressed = false
  private var activeSpaceID: SpaceID
  private var floatingWindows: [SpaceID: Set<CGWindowID>] = [:]
  private var isMissionControlActive = false
  private var isFocusPending = false
  private var focusTask: Task<Void, Never>?

  private var isSuspended: Bool {
    isCommandKeyPressed || isMissionControlActive || !floatingWindows[activeSpaceID, default: []].isEmpty
  }

  init() throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    self.skyLightProxy = try SkyLightProxy()
    self.workspaceMonitor = try WorkspaceMonitor(skyLightProxy: skyLightProxy)
    self.missionControlMonitor = try MissionControlMonitor()
    self.debounceTimer = DispatchSource.makeTimerSource(queue: .main)
    self.activeSpaceID = skyLightProxy.activeSpaceID

    guard
      let cgEventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .listenOnly,
        eventsOfInterest: 1 << CGEventType.mouseMoved.rawValue
          | 1 << CGEventType.leftMouseDragged.rawValue
          | 1 << CGEventType.rightMouseDragged.rawValue
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
        group.addTask { await self?.monitorWorkspace() }
        group.addTask { await self?.monitorMissionControl() }
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

  private func monitorWorkspace() async {
    for await event in workspaceMonitor.events() {
      switch event {
      case .mainScreenChanged, .currentSpaceChanged:
        let activeSpaceID = skyLightProxy.activeSpaceID

        if self.activeSpaceID != activeSpaceID {
          cancelPendingFocus()

          self.activeSpaceID = activeSpaceID

          pruneRemovedFloatingWindowsInActiveSpace()
        }

      case .windowAdded(let windowID, let spaceID):
        if let windowsInfo = CGWindowListCopyWindowInfo(
          [.optionIncludingWindow, .excludeDesktopElements],
          windowID
        ) as? [[String: Any]],
          let windowInfo = windowsInfo.first,
          windowInfo[kCGWindowIsOnscreen as String] as? Bool == true,
          let windowLayer = windowInfo[kCGWindowLayer as String] as? CGWindowLevel,
          windowLayer > kCGNormalWindowLevel,
          windowLayer <= kCGScreenSaverWindowLevel,
          windowLayer != kCGFloatingWindowLevel,
          windowLayer != kCGStatusWindowLevel + 1,
          windowLayer != kCGOverlayWindowLevel + 1
        {
          floatingWindows[spaceID, default: []].insert(windowID)
        }

      case .windowRemoved(let windowID, let spaceID):
        floatingWindows[spaceID]?.remove(windowID)
      }
    }
  }

  private func monitorMissionControl() async {
    for await event in missionControlMonitor.events() {
      switch event {
      case .activated:
        self.isMissionControlActive = true
        cancelPendingFocus()

      case .deactivated:
        self.isMissionControlActive = false
      }
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

      guard (deltaX * deltaX) + (deltaY * deltaY) > Configuration.jitterThresholdSquared else {
        break
      }

      self.lastMouseLocation = event.location
      self.lastMouseMoveTime = .now()

      if !isFocusPending {
        self.isFocusPending = true
        debounceTimer.schedule(deadline: lastMouseMoveTime + Configuration.hoverDelay)
      }

    case .leftMouseDragged, .rightMouseDragged:
      cancelPendingFocus()

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

  private func handleTimerEvent() {
    guard isFocusPending else {
      return
    }

    guard isEnabled, !isSuspended else {
      cancelPendingFocus()
      return
    }

    let focusDeadline = lastMouseMoveTime + Configuration.hoverDelay

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
    guard
      let sessionInfo = CGSessionCopyCurrentDictionary() as? [String: Any],
      sessionInfo["CGSSessionScreenIsLocked"] == nil,
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
      guard
        focusedWindowID != targetWindowID,
        !skyLightProxy.associatedWindows(for: focusedWindowID).contains(targetWindowID),
        !Task.isCancelled
      else {
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

  private func pruneRemovedFloatingWindowsInActiveSpace() {
    let trackedWindowIDs = floatingWindows[activeSpaceID, default: []]

    guard
      !trackedWindowIDs.isEmpty,
      let windowListInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return
    }

    let onScreenWindowIDs = Set(windowListInfo.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })

    self.floatingWindows[activeSpaceID] = trackedWindowIDs.intersection(onScreenWindowIDs)
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
    case .toggle: focusManager?.toggleEnabled()
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

enum IPCCommand: String, CaseIterable {
  case toggle
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
