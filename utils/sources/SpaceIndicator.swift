import SwiftUI
import Synchronization
import System
import UniformTypeIdentifiers

enum Configuration {
  static let subsystem = "industries.britown.SpaceIndicator"
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
      sources.forEach { source in
        source.cancel()
      }
    }

    return stream
  }
}

extension MainActor {
  static func runOrDispatch(_ body: @escaping @Sendable @MainActor () -> Void) {
    if Thread.isMainThread {
      MainActor.assumeIsolated(body)
    } else {
      DispatchQueue.main.async(execute: body)
    }
  }
}

typealias CGSConnectionID = UInt32

typealias CGSNotifyProc =
  @convention(c) (
    _ eventType: UInt32,
    _ data: UnsafeMutableRawPointer?,
    _ dataLength: UInt32,
    _ context: UnsafeMutableRawPointer?
  ) -> Void

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connectionID: CGSConnectionID, _ displayIdentifier: CFString?) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(
  _ connectionID: CGSConnectionID,
  _ spaceMask: CInt,
  _ windowsIDs: CFArray
) -> Unmanaged<CFArray>?

@_silgen_name("CGSRegisterNotifyProc")
@discardableResult
func CGSRegisterNotifyProc(_ proc: CGSNotifyProc, _ event: UInt32, _ context: UnsafeMutableRawPointer?) -> CGError

@_silgen_name("CGSRemoveNotifyProc")
@discardableResult
func CGSRemoveNotifyProc(_ proc: CGSNotifyProc, _ event: UInt32, _ context: UnsafeMutableRawPointer?) -> CGError

enum CGSEventType: UInt32 {
  case packagesStatusBarSpaceChanged = 1308
  case spaceWindowCreated = 1325
  case spaceWindowDestroyed = 1326
  case spaceCreated = 1327
  case spaceDestroyed = 1328
  case spaceCurrentChanged = 1329
}

struct CGSSpaceMask: OptionSet {
  let rawValue: CInt

  static let includesCurrent = CGSSpaceMask(rawValue: 1 << 0)
  static let includesOthers = CGSSpaceMask(rawValue: 1 << 1)
  static let includesUser = CGSSpaceMask(rawValue: 1 << 2)
  static let visible = CGSSpaceMask(rawValue: 1 << 16)

  static let currentSpace: CGSSpaceMask = [.includesUser, .includesCurrent]
  static let otherSpaces: CGSSpaceMask = [.includesOthers, .includesCurrent]
  static let allSpaces: CGSSpaceMask = [.includesUser, .includesOthers, .includesCurrent]
  static let allVisibleSpaces: CGSSpaceMask = [.visible, .allSpaces]
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

typealias DisplayIdentifier = String

extension NSScreen {
  var displayIdentifier: DisplayIdentifier? {
    guard
      let cgDirectDisplayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(cgDirectDisplayID)?.takeRetainedValue()
    else {
      return nil
    }

    return CFUUIDCreateString(nil, uuid) as DisplayIdentifier
  }
}

typealias SpaceID = UInt64

struct Space: Identifiable, Equatable {
  let id: SpaceID
  var isCurrent: Bool
  var apps: [App]
}

struct App: Identifiable, Equatable {
  let processIdentifier: pid_t
  let name: String
  let icon: NSImage

  var id: pid_t { processIdentifier }

  init?(processIdentifier: pid_t) {
    guard
      let runningApplication = NSRunningApplication(processIdentifier: processIdentifier),
      let name = runningApplication.localizedName
    else {
      return nil
    }

    self.processIdentifier = runningApplication.processIdentifier
    self.name = name
    self.icon = runningApplication.icon ?? NSWorkspace.shared.icon(for: .applicationBundle)
  }

  static func == (lhs: App, rhs: App) -> Bool {
    return lhs.id == rhs.id
  }
}

struct Window: Hashable {
  let id: CGWindowID
  let processIdentifier: pid_t
  let spaceID: SpaceID

  init(id: CGWindowID, processIdentifier: pid_t, spaceID: SpaceID) {
    self.id = id
    self.processIdentifier = processIdentifier
    self.spaceID = spaceID
  }

  init?(info windowInfo: [String: Any], cgsConnectionID: CGSConnectionID) {
    guard
      windowInfo[kCGWindowLayer as String] as? CGWindowLevel == kCGNormalWindowLevel,
      let windowID = windowInfo[kCGWindowNumber as String] as? CGWindowID,
      let processIdentifier = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
      let spacesForWindow = CGSCopySpacesForWindows(
        cgsConnectionID,
        CGSSpaceMask.allSpaces.rawValue,
        [windowID] as CFArray
      )?.takeRetainedValue() as? [SpaceID],
      spacesForWindow.count == 1,
      let spaceID = spacesForWindow.first
    else {
      return nil
    }

    self = Window(id: windowID, processIdentifier: processIdentifier, spaceID: spaceID)
  }
}

@MainActor
final class SpaceMonitor {
  enum Error: Swift.Error, LocalizedError {
    case failedToRegisterForNotifications(eventType: CGSEventType, underlyingError: CGError)

    var errorDescription: String? {
      switch self {
      case .failedToRegisterForNotifications(let eventType, let underlyingError):
        "Failed to register for '\(eventType)' notifications: \(underlyingError)"
      }
    }
  }

  enum Event: Sendable {
    case spacesChanged
    case mainScreenChanged
    case currentSpaceChanged(spaceID: SpaceID)
    case windowAdded(windowID: CGWindowID, spaceID: SpaceID)
    case windowRemoved(windowID: CGWindowID, spaceID: SpaceID)
  }

  private let cgsNotifyProc: CGSNotifyProc = { eventType, data, dataLength, context in
    guard
      let eventType = CGSEventType(rawValue: eventType),
      let context,
      let event = event(for: eventType, data: data, dataLength: dataLength)
    else {
      return
    }

    let monitor = Unmanaged<SpaceMonitor>.fromOpaque(context).takeUnretainedValue()

    MainActor.runOrDispatch {
      monitor.continuation?.yield(event)
    }
  }

  private var registeredEventTypes: [CGSEventType] = []
  private var continuation: AsyncStream<Event>.Continuation?

  init() throws {
    for eventType: CGSEventType in [
      .packagesStatusBarSpaceChanged,
      .spaceWindowCreated,
      .spaceWindowDestroyed,
      .spaceCreated,
      .spaceDestroyed,
      .spaceCurrentChanged
    ] {
      let result = CGSRegisterNotifyProc(
        cgsNotifyProc,
        eventType.rawValue,
        Unmanaged.passUnretained(self).toOpaque()
      )

      guard result == .success else {
        unregisterNotifyProc()
        throw Error.failedToRegisterForNotifications(eventType: eventType, underlyingError: result)
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

  private nonisolated static func event(
    for eventType: CGSEventType,
    data: UnsafeMutableRawPointer?,
    dataLength: UInt32
  ) -> Event? {
    switch eventType {
    case .packagesStatusBarSpaceChanged:
      return .mainScreenChanged

    case .spaceWindowCreated, .spaceWindowDestroyed:
      guard let data, dataLength >= MemoryLayout<SpaceID>.size + MemoryLayout<CGWindowID>.size else {
        return nil
      }

      let spaceID = data.load(as: SpaceID.self)
      let windowID = data.load(fromByteOffset: MemoryLayout<SpaceID>.size, as: CGWindowID.self)

      return eventType == .spaceWindowCreated
        ? .windowAdded(windowID: windowID, spaceID: spaceID)
        : .windowRemoved(windowID: windowID, spaceID: spaceID)

    case .spaceCreated, .spaceDestroyed:
      return .spacesChanged

    case .spaceCurrentChanged:
      guard
        let data,
        dataLength >= MemoryLayout<SpaceID>.size + MemoryLayout<UInt8>.size,
        data.load(fromByteOffset: MemoryLayout<SpaceID>.size, as: UInt8.self) != 0
      else {
        return nil
      }

      return .currentSpaceChanged(spaceID: data.load(as: SpaceID.self))
    }
  }

  private func unregisterNotifyProc() {
    for eventType in registeredEventTypes {
      CGSRemoveNotifyProc(cgsNotifyProc, eventType.rawValue, Unmanaged.passUnretained(self).toOpaque())
    }

    self.registeredEventTypes.removeAll()
    self.continuation = nil
  }
}

@MainActor
@Observable
final class SpaceIndicatorModel {
  private(set) var mainScreenDisplayIdentifier = NSScreen.main?.displayIdentifier
  private(set) var displaySpaces: [DisplayIdentifier: [SpaceID]] = [:]
  private(set) var currentSpaceIDs: [DisplayIdentifier: SpaceID] = [:]
  private(set) var spaceWindows: [SpaceID: Set<Window>] = [:]
  private(set) var runningApps: [pid_t: App] = [:]
  private(set) var isRefreshPending = true

  var mainScreenSpaces: [Space] {
    guard let mainScreenDisplayIdentifier else {
      return []
    }

    return displaySpaces[mainScreenDisplayIdentifier, default: []].map { spaceID in
      let isCurrent = spaceID == currentSpaceIDs[mainScreenDisplayIdentifier]
      let windowsOnSpace = spaceWindows[spaceID] ?? []
      let processIdentifiers = Set(windowsOnSpace.compactMap { $0.processIdentifier })
      let apps = processIdentifiers.compactMap { runningApps[$0] }.sorted { $0.name.lexicographicallyPrecedes($1.name) }

      return Space(id: spaceID, isCurrent: isCurrent, apps: apps)
    }
  }

  private let spaceMonitor: SpaceMonitor
  private let cgsConnectionID = CGSMainConnectionID()
  @ObservationIgnored private var monitoringTask: Task<Void, Never>?
  @ObservationIgnored private var refreshTask: Task<Void, Never>?

  init(spaceMonitor: SpaceMonitor) {
    self.spaceMonitor = spaceMonitor
    self.monitoringTask = Task { [weak self] in
      await withDiscardingTaskGroup { group in
        group.addTask { await self?.monitorSpaces() }
        group.addTask { await self?.monitorAppTerminations() }
      }
    }

    scheduleRefresh()
  }

  deinit {
    monitoringTask?.cancel()
    refreshTask?.cancel()
  }

  func diagnosticReport() -> [String] {
    let liveSpacesInfo = spacesInfo(cgsConnectionID: cgsConnectionID)
    let liveWindowIDs = Set(
      windowsInfo(cgsConnectionID: cgsConnectionID).compactMap { $0[kCGWindowNumber as String] as? CGWindowID }
    )

    var lines = [
      "Tracked windows: \(spaceWindows.values.reduce(0) { $0 + $1.count })",
      "Tracked apps: \(runningApps.count)",
      "Refresh pending: \(isRefreshPending)"
    ]

    for displayIdentifier in Set(displaySpaces.keys).union(liveSpacesInfo.displaySpaces.keys).sorted() {
      let cachedCurrentSpaceID = currentSpaceIDs[displayIdentifier].map(String.init) ?? "<none>"
      let liveCurrentSpaceID = liveSpacesInfo.currentSpaceIDs[displayIdentifier].map(String.init) ?? "<none>"
      let mainScreenMarker = displayIdentifier == mainScreenDisplayIdentifier ? " (main)" : ""

      lines.append("Display \(displayIdentifier)\(mainScreenMarker):")
      lines.append("  Cached spaces: \(displaySpaces[displayIdentifier] ?? []), current: \(cachedCurrentSpaceID)")
      lines.append(
        "  Live spaces: \(liveSpacesInfo.displaySpaces[displayIdentifier] ?? []), current: \(liveCurrentSpaceID)"
      )

      for spaceID in displaySpaces[displayIdentifier] ?? [] {
        let windows = spaceWindows[spaceID] ?? []
        let appNames = Set(windows.map(\.processIdentifier)).compactMap { runningApps[$0]?.name }.sorted()

        lines.append(
          "  Space \(spaceID): \(windows.count) window(s)\(appNames.isEmpty ? "" : " (\(appNames.joined(separator: ", ")))")"
        )
      }
    }

    let staleWindowsInfo =
      spaceWindows
      .mapValues { windows in
        windows.filter { !liveWindowIDs.contains($0.id) }
          .map {
            "\($0.id) (\(runningApps[$0.processIdentifier]?.name ?? String($0.processIdentifier)))"
          }
      }

    lines.append("Stale windows: \(staleWindowsInfo.values.reduce(0) { $0 + $1.count })")
    Array(staleWindowsInfo.keys)
      .sorted(by: <)
      .forEach { spaceID in
        if let windows = staleWindowsInfo[spaceID], !windows.isEmpty {
          lines.append("  Space \(spaceID): \(windows.count) window(s)")
          windows.forEach { lines.append("   \($0)") }
        }
      }

    let trackedProcessIdentifiers = Set(spaceWindows.values.flatMap { $0 }.map(\.processIdentifier))
    let orphanedAppsInfo =
      runningApps
      .filter { !trackedProcessIdentifiers.contains($0.key) }
      .map { "\($0.value.name) (PID: \($0.key))" }
      .sorted()

    lines.append("Orphaned apps: \(orphanedAppsInfo.count)")
    orphanedAppsInfo.forEach { lines.append("  \($0)") }

    return lines
  }

  private func monitorSpaces() async {
    for await event in spaceMonitor.events() {
      switch event {
      case .spacesChanged: scheduleRefresh()
      case .mainScreenChanged: self.mainScreenDisplayIdentifier = NSScreen.main?.displayIdentifier
      case .currentSpaceChanged(let spaceID): handleCurrentSpaceChanged(spaceID: spaceID)
      case .windowAdded(let windowID, let spaceID): handleWindowAdded(windowID: windowID, spaceID: spaceID)
      case .windowRemoved(let windowID, let spaceID): handleWindowRemoved(windowID: windowID, spaceID: spaceID)
      }
    }
  }

  private func monitorAppTerminations() async {
    for await notification in NSWorkspace.shared.notificationCenter.notifications(
      named: NSWorkspace.didTerminateApplicationNotification
    ) {
      guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
        continue
      }

      self.runningApps.removeValue(forKey: app.processIdentifier)

      for (trackedSpaceID, windows) in spaceWindows {
        self.spaceWindows[trackedSpaceID] = windows.filter { $0.processIdentifier != app.processIdentifier }
      }
    }
  }

  private func spacesInfo(
    cgsConnectionID: CGSConnectionID
  ) -> (displaySpaces: [DisplayIdentifier: [SpaceID]], currentSpaceIDs: [DisplayIdentifier: SpaceID]) {
    guard
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        cgsConnectionID,
        nil
      )?.takeRetainedValue()
        as? [[String: Any]]
    else {
      return ([:], [:])
    }

    var displaySpaces: [DisplayIdentifier: [SpaceID]] = [:]
    var spaceIDs: [DisplayIdentifier: SpaceID] = [:]

    for displayInfo in managedDisplaySpaces {
      guard
        let displayIdentifier = displayInfo["Display Identifier"] as? DisplayIdentifier,
        let spacesInfo = displayInfo["Spaces"] as? [[String: Any]]
      else {
        continue
      }

      displaySpaces[displayIdentifier] = spacesInfo.compactMap { $0["id64"] as? SpaceID }

      if let currentSpaceInfo = displayInfo["Current Space"] as? [String: Any],
        let currentSpaceID = currentSpaceInfo["id64"] as? SpaceID
      {
        spaceIDs[displayIdentifier] = currentSpaceID
      }
    }

    return (displaySpaces, spaceIDs)
  }

  private func windowsInfo(cgsConnectionID: CGSConnectionID) -> [[String: Any]] {
    guard
      let windowsInfo = CGWindowListCopyWindowInfo(
        [.optionAll, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return []
    }

    return windowsInfo
  }

  private func refreshSpaces() {
    let spacesInfo = spacesInfo(cgsConnectionID: cgsConnectionID)

    guard !spacesInfo.displaySpaces.isEmpty else {
      return
    }

    self.displaySpaces = spacesInfo.displaySpaces
    self.currentSpaceIDs = spacesInfo.currentSpaceIDs
  }

  private func refreshWindows() {
    self.spaceWindows.removeAll()

    for windowInfo in windowsInfo(cgsConnectionID: cgsConnectionID) {
      guard let window = Window(info: windowInfo, cgsConnectionID: cgsConnectionID) else {
        continue
      }

      trackWindow(window)
    }
  }

  private func scheduleRefresh() {
    self.isRefreshPending = true

    refreshTask?.cancel()
    self.refreshTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(100))

      guard !Task.isCancelled, let self else {
        return
      }

      refreshSpaces()
      refreshWindows()

      self.isRefreshPending = false
    }
  }

  private func handleCurrentSpaceChanged(spaceID: SpaceID) {
    guard
      !isRefreshPending,
      let displayIdentifier = displaySpaces.first(where: { $0.value.contains(spaceID) })?.key
    else {
      return
    }

    self.currentSpaceIDs[displayIdentifier] = spaceID

    guard
      let windowsInfo = CGWindowListCopyWindowInfo(
        [.optionAll, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return
    }

    let liveWindowIDs = Set(windowsInfo.compactMap { $0[kCGWindowNumber as String] as? CGWindowID })

    for (trackedSpaceID, windows) in spaceWindows {
      let liveWindows = windows.filter { liveWindowIDs.contains($0.id) }

      guard liveWindows.count != windows.count else {
        continue
      }

      self.spaceWindows[trackedSpaceID] = liveWindows
    }
  }

  private func handleWindowAdded(windowID: CGWindowID, spaceID: SpaceID) {
    guard
      !isRefreshPending,
      let windowsInfo = CGWindowListCopyWindowInfo(
        [.optionIncludingWindow, .excludeDesktopElements],
        windowID
      ) as? [[String: Any]],
      let windowInfo = windowsInfo.first,
      let window = Window(info: windowInfo, cgsConnectionID: cgsConnectionID),
      window.spaceID == spaceID
    else {
      return
    }

    trackWindow(window)
  }

  private func handleWindowRemoved(windowID: CGWindowID, spaceID: SpaceID) {
    guard
      !isRefreshPending,
      let windowsOnSpace = spaceWindows[spaceID],
      let window = windowsOnSpace.first(where: { $0.id == windowID })
    else {
      return
    }

    self.spaceWindows[spaceID]?.remove(window)
  }

  private func trackWindow(_ window: Window) {
    self.spaceWindows[window.spaceID, default: []].insert(window)

    if runningApps[window.processIdentifier] == nil, let app = App(processIdentifier: window.processIdentifier) {
      self.runningApps[app.id] = app
    }
  }
}

struct SpaceIndicatorView: View {
  private enum IconMetrics {
    static let size: CGFloat = 17.0
    static let paddingCropScale: CGFloat = 32 / 28
    static let cornerRatio: CGFloat = 7 / 28
    static let overlapGap: CGFloat = 1.0
    static let cutoutMaskSize: CGFloat = size + (overlapGap * 2)
    static let cutoutMaskCornerRadius: CGFloat = (cutoutMaskSize * cornerRatio) + (overlapGap / 2)
  }

  let model: SpaceIndicatorModel
  let onWidthChanged: (CGFloat) -> Void

  var body: some View {
    HStack(spacing: 12) {
      ForEach(model.mainScreenSpaces.enumerated(), id: \.element.id) { index, space in
        HStack(spacing: 6) {
          Text("\(index + 1)")
            .font(.subheadline)
            .fontWeight(space.isCurrent ? .medium : .regular)
            .foregroundStyle(Color(.textColor))
            .frame(width: 8)

          if !space.apps.isEmpty {
            HStack(spacing: -4) {
              ForEach(space.apps) { app in
                Image(nsImage: app.icon)
                  .resizable()
                  .scaleEffect(IconMetrics.paddingCropScale)
                  .frame(width: IconMetrics.size, height: IconMetrics.size)
                  .clipShape(.rect(cornerRadius: IconMetrics.size * IconMetrics.cornerRatio))
                  .background {
                    RoundedRectangle(cornerRadius: IconMetrics.cutoutMaskCornerRadius)
                      .fill(.black)
                      .frame(width: IconMetrics.cutoutMaskSize, height: IconMetrics.cutoutMaskSize)
                      .blendMode(.destinationOut)
                  }
              }
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 0.5)
          }
        }
        .opacity(space.isCurrent ? 1 : 0.45)
        .animation(.snappy(duration: 0.2), value: space.isCurrent)
      }
    }
    .padding(.horizontal, 14)
    .fixedSize()
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { newWidth in
      onWidthChanged(newWidth)
    }
  }
}

@MainActor
final class StatusItemManager {
  private static let autosaveName = "SpaceIndicator"
  private static let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"

  private let startDate = Date.now
  private let spaceIndicatorModel: SpaceIndicatorModel
  private var hostingView: NSHostingView<SpaceIndicatorView>?
  private var statusItem: NSStatusItem?
  private var lastReportedWidth: CGFloat = .zero

  init(spaceIndicatorModel: SpaceIndicatorModel) {
    self.spaceIndicatorModel = spaceIndicatorModel

    let spaceIndicatorView = SpaceIndicatorView(
      model: spaceIndicatorModel,
      onWidthChanged: { [weak self] width in
        self?.setStatusItemWidth(to: width)
      }
    )
    let hostingView = NSHostingView(rootView: spaceIndicatorView)
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.autosaveName = Self.autosaveName
    statusItem.behavior = .terminationOnRemoval
    statusItem.button?.isEnabled = false
    statusItem.button?.addSubview(hostingView)

    self.hostingView = hostingView
    self.statusItem = statusItem
  }

  func logDiagnosticReport() {
    Log.message(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Status item present: \(statusItem != nil)
        Status item visible: \(statusItem.map { "\($0.isVisible)" } ?? "<none>")
        Last reported width: \(lastReportedWidth)
      \(spaceIndicatorModel.diagnosticReport().map { "  \($0)" }.joined(separator: "\n"))
      """
    )
  }

  func toggleVisibility() {
    let savedPosition = UserDefaults.standard.object(forKey: Self.preferredPositionKey)

    defer {
      if let savedPosition {
        UserDefaults.standard.set(savedPosition, forKey: Self.preferredPositionKey)
      }
    }

    statusItem?.isVisible.toggle()
  }

  private func setStatusItemWidth(to width: CGFloat) {
    guard self.lastReportedWidth != width, let hostingView, let statusItemButton = statusItem?.button else {
      return
    }

    let newSize = NSSize(width: width, height: 22)

    hostingView.setFrameSize(newSize)
    statusItemButton.setFrameSize(newSize)

    self.lastReportedWidth = width
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var singleInstanceLock: SingleInstanceLock?
  private var statusItemManager: StatusItemManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let spaceMonitor = try SpaceMonitor()
      let spaceIndicatorModel = SpaceIndicatorModel(spaceMonitor: spaceMonitor)

      self.statusItemManager = StatusItemManager(spaceIndicatorModel: spaceIndicatorModel)
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
    observeProcessSignals()
    observeIPCCommands()
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.singleInstanceLock = nil
    self.statusItemManager = nil
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
      for await notification
        in DistributedNotificationCenter
        .default()
        .notifications(named: IPCCommand.notificationName)
      {
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
    case .toggle: statusItemManager?.toggleVisibility()
    case .printLog: statusItemManager?.logDiagnosticReport()
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
    application.setActivationPolicy(.accessory)
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
