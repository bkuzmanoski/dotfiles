// Shared: Accessibility Agent CGError EventTap Log NSRunningApplication ScreenCapturePermission SkyLightFramework

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.FocusFollowsMouse"
  static let exemptBundleIdentifiers: Set<String> = ["com.anthropic.claudefordesktop"]
  static let focusableFloatingWindows: Set<WindowIdentity> = [
    WindowIdentity(bundleIdentifier: "com.raycast.macos", title: "AI Chat"),
    WindowIdentity(bundleIdentifier: "com.raycast.macos", title: "Notes")
  ]
  static let hoverDelay: DispatchTimeInterval = .milliseconds(300)
  static let crossDisplayHoverDelay: DispatchTimeInterval = .milliseconds(60)
  static let focusChangeGracePeriod: DispatchTimeInterval = .seconds(500)
  static let jitterThreshold = 3
}

struct WindowIdentity: Hashable {
  let bundleIdentifier: String
  let title: String
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

@MainActor
final class FocusChangeMonitor {
  struct FocusChange {
    let processIdentifier: pid_t
    let windowID: CGWindowID?
  }

  private static let launchTimeout: Duration = .seconds(2)

  private var observedProcessIdentifier: pid_t?
  private var applicationElement: AXUIElement?
  private var axObserver: AXObserver?
  private var runLoopSource: CFRunLoopSource?
  private var launchObservation: NSKeyValueObservation?
  private var launchTimeoutTask: Task<Void, Never>?
  private var activationObservationTask: Task<Void, Never>?
  private var continuation: AsyncStream<FocusChange>.Continuation?

  init() {
    self.activationObservationTask = Task { [weak self] in
      for await notification in NSWorkspace.shared.notificationCenter.notifications(
        named: NSWorkspace.didActivateApplicationNotification
      ) {
        guard let self else {
          break
        }

        guard
          let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        else {
          continue
        }

        handleActivation(of: application)
      }
    }

    if let application = NSWorkspace.shared.frontmostApplication {
      observeFocusedWindowChanges(of: application)
    }
  }

  isolated deinit {
    activationObservationTask?.cancel()
    continuation?.finish()
    stopObserving()
  }

  func focusChanges() -> AsyncStream<FocusChange> {
    continuation?.finish()

    let (stream, continuation) = AsyncStream.makeStream(of: FocusChange.self)

    self.continuation = continuation

    return stream
  }

  private func handleActivation(of application: NSRunningApplication) {
    continuation?.yield(FocusChange(processIdentifier: application.processIdentifier, windowID: nil))
    observeFocusedWindowChanges(of: application)
  }

  private func observeFocusedWindowChanges(of application: NSRunningApplication) {
    let processIdentifier = application.processIdentifier

    guard processIdentifier != observedProcessIdentifier else {
      return
    }

    stopObserving()

    if !application.isFinishedLaunching {
      self.observedProcessIdentifier = processIdentifier

      self.launchObservation = application.observe(\.isFinishedLaunching) { [weak self] _, _ in
        Task { @MainActor in
          self?.handleLaunchFinished(of: processIdentifier)
        }
      }

      self.launchTimeoutTask = Task { [weak self] in
        do {
          try await Task.sleep(for: Self.launchTimeout)
        } catch {
          return
        }

        self?.handleLaunchTimeout(of: processIdentifier)
      }

      return
    }

    addObserver(for: processIdentifier)
  }

  private func handleLaunchFinished(of processIdentifier: pid_t) {
    guard
      launchObservation != nil,
      processIdentifier == observedProcessIdentifier,
      NSRunningApplication(processIdentifier: processIdentifier)?.isFinishedLaunching == true
    else {
      return
    }

    continuation?.yield(FocusChange(processIdentifier: processIdentifier, windowID: nil))
    addObserver(for: processIdentifier)
  }

  private func handleLaunchTimeout(of processIdentifier: pid_t) {
    guard launchObservation != nil, processIdentifier == observedProcessIdentifier else {
      return
    }

    addObserver(for: processIdentifier)
  }

  private func addObserver(for processIdentifier: pid_t) {
    stopObserving()

    let applicationElement = AXUIElementCreateApplication(processIdentifier)

    var axObserver: AXObserver?

    let createResult = AXObserverCreate(
      processIdentifier,
      { _, element, _, refcon in
        guard let refcon else {
          return
        }

        MainActor.assumeIsolated {
          Unmanaged<FocusChangeMonitor>.fromOpaque(refcon).takeUnretainedValue().handleFocusedWindowChange(element)
        }
      },
      &axObserver
    )

    guard createResult == .success, let axObserver else {
      Log.error("Failed to create observer for PID \(processIdentifier): \(createResult.localizedDescription)")
      return
    }

    let addNotificationResult = AXObserverAddNotification(
      axObserver,
      applicationElement,
      kAXFocusedWindowChangedNotification as CFString,
      Unmanaged.passUnretained(self).toOpaque()
    )

    guard addNotificationResult == .success else {
      Log.error(
        "Failed to observe focused window changes for PID \(processIdentifier): \(addNotificationResult.localizedDescription)"
      )
      return
    }

    let runLoopSource = AXObserverGetRunLoopSource(axObserver)

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

    self.observedProcessIdentifier = processIdentifier
    self.applicationElement = applicationElement
    self.axObserver = axObserver
    self.runLoopSource = runLoopSource
  }

  private func stopObserving() {
    if let axObserver, let applicationElement {
      AXObserverRemoveNotification(axObserver, applicationElement, kAXFocusedWindowChangedNotification as CFString)
    }

    if let runLoopSource {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    }

    launchObservation?.invalidate()
    launchTimeoutTask?.cancel()

    self.launchObservation = nil
    self.launchTimeoutTask = nil
    self.observedProcessIdentifier = nil
    self.applicationElement = nil
    self.axObserver = nil
    self.runLoopSource = nil
  }

  private func handleFocusedWindowChange(_ windowElement: AXUIElement) {
    guard let observedProcessIdentifier else {
      return
    }

    continuation?.yield(
      FocusChange(processIdentifier: observedProcessIdentifier, windowID: try? windowElement.windowID())
    )
  }
}

@MainActor
final class FocusManager {
  private struct FocusedTarget {
    let processIdentifier: pid_t
    let windowID: CGWindowID
    let time: DispatchTime
  }

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
  private let crossDisplayHoverDelay: DispatchTimeInterval
  private let focusChangeGracePeriod: DispatchTimeInterval
  private let jitterThresholdSquared: CGFloat
  private let exemptBundleIdentifiers: Set<String>
  private let focusableFloatingWindows: Set<WindowIdentity>
  private let eventTap: EventTap
  private let skyLightFramework: SkyLightFramework
  private let focusChangeMonitor: FocusChangeMonitor
  private let debounceTimer: any DispatchSourceTimer
  private var spaceObservationTask: Task<Void, Never>?
  private var screenParametersObservationTask: Task<Void, Never>?
  private var focusChangeObservationTask: Task<Void, Never>?
  private var displayBounds: [CGRect] = []
  private var cursorDisplayIndex: Int?
  private var lastMouseLocation: CGPoint = .zero
  private var lastMouseMoveTime: DispatchTime = .now()
  private var isCommandKeyPressed = false
  private var hasPendingDisplayCrossing = false
  private var pendingFocusDelay: DispatchTimeInterval?
  private var lastExternalFocusChangeTime: DispatchTime?
  private var lastFocusedTarget: FocusedTarget?
  private var focusTask: Task<Void, Never>?

  private var isInFocusChangeGracePeriod: Bool {
    lastExternalFocusChangeTime.map { DispatchTime.now() < $0 + focusChangeGracePeriod } ?? false
  }

  init(
    hoverDelay: DispatchTimeInterval,
    crossDisplayHoverDelay: DispatchTimeInterval,
    focusChangeGracePeriod: DispatchTimeInterval,
    jitterThreshold: Int,
    exemptBundleIdentifiers: Set<String>,
    focusableFloatingWindows: Set<WindowIdentity>
  ) throws {
    if !focusableFloatingWindows.isEmpty {
      try ScreenCapturePermission.ensureGranted()
    }

    self.hoverDelay = hoverDelay
    self.crossDisplayHoverDelay = crossDisplayHoverDelay
    self.focusChangeGracePeriod = focusChangeGracePeriod
    self.jitterThresholdSquared = CGFloat(jitterThreshold * jitterThreshold)
    self.exemptBundleIdentifiers = exemptBundleIdentifiers
    self.focusableFloatingWindows = focusableFloatingWindows
    self.eventTap = try EventTap(
      location: .cgSessionEventTap,
      observing: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .flagsChanged]
    )
    self.skyLightFramework = try SkyLightFramework()
    self.focusChangeMonitor = FocusChangeMonitor()
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

    self.screenParametersObservationTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: NSApplication.didChangeScreenParametersNotification
      ) {
        guard let self else {
          break
        }

        refreshDisplayBounds()
      }
    }

    let focusChanges = focusChangeMonitor.focusChanges()

    self.focusChangeObservationTask = Task { [weak self] in
      for await focusChange in focusChanges {
        guard let self else {
          break
        }

        handleFocusChange(focusChange)
      }
    }

    refreshDisplayBounds()
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
    screenParametersObservationTask?.cancel()
    focusChangeObservationTask?.cancel()
    debounceTimer.cancel()
    focusTask?.cancel()
  }

  func toggleEnabled() {
    self.isEnabled.toggle()

    resetDisplayCrossingTracking()
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
        Focus pending: \(pendingFocusDelay != nil)
        Focus change grace period active: \(isInFocusChangeGracePeriod)
        Hover delay: \(hoverDelay)
        Cross-display hover delay: \(crossDisplayHoverDelay)
        Focus change grace period: \(focusChangeGracePeriod)
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

  private func refreshDisplayBounds() {
    resetDisplayCrossingTracking()

    var displayCount: UInt32 = 0

    guard CGGetActiveDisplayList(0, nil, &displayCount) == .success else {
      self.displayBounds = []
      return
    }

    var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))

    guard CGGetActiveDisplayList(displayCount, &displayIDs, &displayCount) == .success else {
      self.displayBounds = []
      return
    }

    self.displayBounds = displayIDs.prefix(Int(displayCount)).map(CGDisplayBounds)
  }

  private func updateCursorDisplayIndex(for location: CGPoint) -> Bool {
    guard let displayIndex = displayBounds.firstIndex(where: { $0.contains(location) }) else {
      return false
    }

    let didCrossDisplay = cursorDisplayIndex != nil && displayIndex != cursorDisplayIndex

    self.cursorDisplayIndex = displayIndex

    return didCrossDisplay
  }

  private func resetDisplayCrossingTracking() {
    self.cursorDisplayIndex = nil
    self.hasPendingDisplayCrossing = false
  }

  private func handleCGEvent(_ event: CGEvent) {
    switch event.type {
    case .mouseMoved:
      let didCrossDisplay = updateCursorDisplayIndex(for: event.location)

      guard isEnabled, !isCommandKeyPressed else {
        break
      }

      if didCrossDisplay {
        self.hasPendingDisplayCrossing = true
      }

      let deltaX = event.location.x - lastMouseLocation.x
      let deltaY = event.location.y - lastMouseLocation.y

      guard (deltaX * deltaX) + (deltaY * deltaY) > jitterThresholdSquared else {
        break
      }

      self.lastMouseLocation = event.location
      self.lastMouseMoveTime = .now()

      let isDisplayCrossing = hasPendingDisplayCrossing

      self.hasPendingDisplayCrossing = false

      if isDisplayCrossing {
        self.pendingFocusDelay = crossDisplayHoverDelay
        debounceTimer.schedule(deadline: lastMouseMoveTime + crossDisplayHoverDelay)
      } else if pendingFocusDelay == nil {
        self.pendingFocusDelay = hoverDelay
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

  private func handleFocusChange(_ focusChange: FocusChangeMonitor.FocusChange) {
    let now = DispatchTime.now()

    if let lastFocusedTarget, now < lastFocusedTarget.time + focusChangeGracePeriod {
      let isOwnFocusChange =
        focusChange.windowID.map { $0 == lastFocusedTarget.windowID }
        ?? (focusChange.processIdentifier == lastFocusedTarget.processIdentifier)

      guard !isOwnFocusChange else {
        return
      }
    }

    self.lastExternalFocusChangeTime = now
  }

  private func recordFocusedTarget(processIdentifier: pid_t, windowID: CGWindowID) {
    self.lastFocusedTarget = FocusedTarget(processIdentifier: processIdentifier, windowID: windowID, time: .now())
  }

  private func handleTimerEvent() {
    guard let pendingFocusDelay else {
      return
    }

    guard isEnabled, !isCommandKeyPressed else {
      cancelPendingFocus()
      return
    }

    let focusDeadline = lastMouseMoveTime + pendingFocusDelay

    guard DispatchTime.now() >= focusDeadline else {
      debounceTimer.schedule(deadline: focusDeadline)
      return
    }

    self.pendingFocusDelay = nil

    if isInFocusChangeGracePeriod {
      return
    }

    focusTask?.cancel()
    self.focusTask = Task { [weak self, lastMouseLocation] in
      await self?.focusWindow(at: lastMouseLocation)
    }
  }

  private nonisolated func focusWindow(at point: CGPoint) async {
    var targetPSN = ProcessSerialNumber()

    guard
      let (targetWindowID, targetPID) = skyLightFramework.findWindow(at: point),
      isFocusableWindow(targetWindowID),
      GetProcessForPID(targetPID, &targetPSN) == noErr
    else {
      return
    }

    var focusedWindow: (windowID: CGWindowID, processSerialNumber: ProcessSerialNumber)?
    var isSameProcess: DarwinBoolean = false

    if var focusedPSN = skyLightFramework.frontProcess,
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
          !skyLightFramework.associatedWindows(for: focusedWindowID).contains(targetWindowID)
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

    await recordFocusedTarget(processIdentifier: targetPID, windowID: targetWindowID)

    if let focusedWindow,
      skyLightFramework.postEvent(
        .focusTransition(windowID: focusedWindow.windowID, type: .resignKey),
        to: focusedWindow.processSerialNumber
      ) == .success
    {
      await withTaskCancellationShield {
        try? await Task.sleep(for: .milliseconds(10))
      }

      skyLightFramework.postEvent(.focusTransition(windowID: targetWindowID, type: .becomeKey), to: targetPSN)
    }

    guard
      skyLightFramework.setFrontProcess(targetPSN, windowID: targetWindowID, options: .userGenerated) == .success,
      skyLightFramework.postEvent(
        .simulatedClick(windowID: targetWindowID, type: .leftMouseDown),
        to: targetPSN
      ) == .success
    else {
      return
    }

    skyLightFramework.postEvent(.simulatedClick(windowID: targetWindowID, type: .leftMouseUp), to: targetPSN)
  }

  private func cancelPendingFocus() {
    focusTask?.cancel()

    self.pendingFocusDelay = nil
    self.hasPendingDisplayCrossing = false
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
    if skyLightFramework.windowLevel(for: windowID) == kCGNormalWindowLevel {
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
        crossDisplayHoverDelay: Configuration.crossDisplayHoverDelay,
        focusChangeGracePeriod: Configuration.focusChangeGracePeriod,
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
