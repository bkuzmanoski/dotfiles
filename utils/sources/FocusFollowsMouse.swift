// Shared: Accessibility Agent CGError EventTap Log NSRunningApplication ScreenCapturePermission

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.FocusFollowsMouse"
  static let exemptBundleIdentifiers: Set<String> = ["com.anthropic.claudefordesktop"]
  static let focusableFloatingWindows: Set<WindowIdentity> = [
    WindowIdentity(bundleIdentifier: "com.raycast.macos", title: "AI Chat"),
    WindowIdentity(bundleIdentifier: "com.raycast.macos", title: "Notes")
  ]
  static let hoverDelay: DispatchTimeInterval = .milliseconds(300)
  static let jitterThreshold = 3
}

struct WindowIdentity: Hashable {
  let bundleIdentifier: String
  let title: String
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
  private(set) var isEnabled = true

  private let startDate = Date.now
  private let suspendingWindowLevels: Set<CGWindowLevel> = [
    CGWindowLevelForKey(.modalPanelWindow),
    CGWindowLevelForKey(.popUpMenuWindow),
    CGWindowLevelForKey(.screenSaverWindow),
    CGWindowLevelForKey(.overlayWindow)
  ]
  private let windowManagerSuspendingWindowLevels: Set<CGWindowLevel> = [18, 19]
  private let hoverDelay: DispatchTimeInterval
  private let jitterThresholdSquared: CGFloat
  private let exemptBundleIdentifiers: Set<String>
  private let focusableFloatingWindows: Set<WindowIdentity>
  private let eventTap: EventTap
  private let skyLightProxy: SkyLightProxy
  private let debounceTimer: any DispatchSourceTimer
  private var spaceObservationTask: Task<Void, Never>?
  private var lastMouseLocation: CGPoint = .zero
  private var lastMouseMoveTime: DispatchTime = .now()
  private var isCommandKeyPressed = false
  private var isFocusPending = false
  private var focusTask: Task<Void, Never>?

  init(
    hoverDelay: DispatchTimeInterval,
    jitterThreshold: Int,
    exemptBundleIdentifiers: Set<String>,
    focusableFloatingWindows: Set<WindowIdentity>
  ) throws {
    if !focusableFloatingWindows.isEmpty {
      try ScreenCapturePermission.ensureGranted()
    }

    self.hoverDelay = hoverDelay
    self.jitterThresholdSquared = CGFloat(jitterThreshold * jitterThreshold)
    self.exemptBundleIdentifiers = exemptBundleIdentifiers
    self.focusableFloatingWindows = focusableFloatingWindows
    self.eventTap = try EventTap(
      location: .cgSessionEventTap,
      options: .listenOnly,
      eventTypes: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .flagsChanged]
    )
    self.skyLightProxy = try SkyLightProxy()
    self.debounceTimer = DispatchSource.makeTimerSource(queue: .main)

    self.spaceObservationTask = Task { [weak self] in
      for await _ in NSWorkspace.shared.notificationCenter.notifications(
        named: NSWorkspace.activeSpaceDidChangeNotification
      ) {
        guard let self else {
          break
        }

        cancelPendingFocus()
      }
    }

    AXUIElement.setGlobalMessagingTimeout(seconds: 0.5)

    eventTap.eventObserver = { [weak self] event in
      self?.handleCGEvent(event)
    }

    eventTap.interruptionHandler = { [weak self] in
      self?.updateCommandKeyState()
    }

    debounceTimer.setEventHandler { [weak self] in
      self?.handleTimerEvent()
    }

    eventTap.isEnabled = true
    debounceTimer.resume()
  }

  isolated deinit {
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

    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AccessibilityPermission.isGranted)
        Screen capture permission: \(ScreenCapturePermission.isGranted)
        Enabled: \(isEnabled)
        Event tap active: \(eventTap.isActive)
        Suspended: \(isCommandKeyPressed || isScreenLocked || !suspendingWindows.isEmpty)
          Command key pressed: \(isCommandKeyPressed)
          Screen locked: \(isScreenLocked)
          Suspending windows on screen: \(suspendingWindows.isEmpty ? "none" : suspendingWindows.joined(separator: ", "))
        Focus pending: \(isFocusPending)
        Hover delay: \(hoverDelay)
        Exempt bundle IDs: \(exemptBundleIdentifiers.sorted().joined(separator: ", "))
        Focusable floating windows: \(focusableFloatingWindows.map { "\($0.bundleIdentifier) \"\($0.title)\"" }.sorted().joined(separator: ", "))
      """
    )
  }

  private func updateEventTapState() {
    eventTap.isEnabled = isEnabled
    updateCommandKeyState()
  }

  private func updateCommandKeyState() {
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
      isFocusableWindow(targetWindowID),
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

    let targetApplication = NSRunningApplication(processIdentifier: targetPID)

    guard
      !Task.isCancelled,
      targetApplication?.isSystemAgent != true,
      !exemptBundleIdentifiers.contains(targetApplication?.bundleIdentifier ?? ""),
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
      return ownerBundleIdentifier(ofWindow: windowInfo) == "com.apple.WindowManager"
    }

    guard suspendingWindowLevels.contains(windowLevel), windowInfo[kCGWindowAlpha as String] as? Double ?? 1 > 0 else {
      return false
    }

    return !isFocusableFloatingWindow(info: windowInfo)
  }

  private nonisolated func isFocusableWindow(_ windowID: CGWindowID) -> Bool {
    if skyLightProxy.windowLevel(for: windowID) == kCGNormalWindowLevel {
      return true
    }

    guard
      !focusableFloatingWindows.isEmpty,
      let windowInfo = (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]])?.first
    else {
      return false
    }

    return isFocusableFloatingWindow(info: windowInfo)
  }

  private nonisolated func isFocusableFloatingWindow(info windowInfo: [String: Any]) -> Bool {
    guard
      !focusableFloatingWindows.isEmpty,
      let title = windowInfo[kCGWindowName as String] as? String,
      let bundleIdentifier = ownerBundleIdentifier(ofWindow: windowInfo)
    else {
      return false
    }

    return focusableFloatingWindows.contains(WindowIdentity(bundleIdentifier: bundleIdentifier, title: title))
  }

  private nonisolated func ownerBundleIdentifier(ofWindow windowInfo: [String: Any]) -> String? {
    guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t else {
      return nil
    }

    return NSRunningApplication(processIdentifier: ownerPID)?.bundleIdentifier
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var focusManager: FocusManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.focusManager = try FocusManager(
        hoverDelay: Configuration.hoverDelay,
        jitterThreshold: Configuration.jitterThreshold,
        exemptBundleIdentifiers: Configuration.exemptBundleIdentifiers,
        focusableFloatingWindows: Configuration.focusableFloatingWindows
      )
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.focusManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .toggle: focusManager?.toggleEnabled()
    case .printLog: focusManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case toggle
  case printLog = "print-log"
  case quit
}

@main
enum FocusFollowsMouse {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
