import SwiftUI

enum Constants {
  static let subsystem = "industries.britown.SpaceIndicator"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
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
      case .instanceAlreadyRunning: "Instance already running."
      case .failedToAcquireLock(let errno): "Failed to acquire lock (\(String(cString: strerror(errno))))."
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

typealias CGSNotifyProcPtr =
  @convention(c) (
    _ eventType: UInt32,
    _ data: UnsafeMutableRawPointer?,
    _ dataLength: UInt32,
    _ userData: UnsafeMutableRawPointer?
  ) -> Void

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> UInt32

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ cid: UInt32, _ display: CFString?) -> Unmanaged<CFArray>?

@_silgen_name("CGSCopySpacesForWindows")
func CGSCopySpacesForWindows(_ cid: UInt32, _ mask: CInt, _ windows: CFArray) -> Unmanaged<CFArray>?

@_silgen_name("CGSRegisterNotifyProc")
@discardableResult
func CGSRegisterNotifyProc(_ proc: CGSNotifyProcPtr, _ event: UInt32, _ userData: UnsafeMutableRawPointer?) -> CGError

@_silgen_name("CGSRemoveNotifyProc")
@discardableResult
func CGSRemoveNotifyProc(_ proc: CGSNotifyProcPtr, _ event: UInt32, _ userData: UnsafeMutableRawPointer?) -> CGError

enum CGSEventType: UInt32, CaseIterable {
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

typealias DisplayIdentifier = String

extension NSScreen {
  var displayIdentifier: DisplayIdentifier? {
    let key = NSDeviceDescriptionKey("NSScreenNumber")

    guard
      let number = deviceDescription[key] as? NSNumber,
      let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
    else {
      return nil
    }

    return CFUUIDCreateString(nil, uuid) as String
  }
}

typealias SpaceID = UInt64

struct Space: Identifiable, Equatable {
  let id: SpaceID
  var isActive: Bool
  var apps: [App]
}

struct App: Identifiable, Equatable {
  let processIdentifier: pid_t
  let name: String
  let icon: NSImage

  var id: pid_t { processIdentifier }

  init?(processIdentifier: pid_t) {
    guard let runningApplication = NSRunningApplication(processIdentifier: processIdentifier),
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

typealias WindowID = UInt32

struct Window: Hashable {
  let id: WindowID
  let processIdentifier: pid_t
  let spaceID: SpaceID

  init?(windowInfo: [String: Any], spaceID: SpaceID) {
    guard
      let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
      let processIdentifier = (windowInfo[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
      (windowInfo[kCGWindowLayer as String] as? NSNumber)?.int32Value == kCGNormalWindowLevel,
      (windowInfo[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0 > 0.0
    else {
      return nil
    }

    self.id = windowID
    self.processIdentifier = processIdentifier
    self.spaceID = spaceID
  }
}

final class SpaceMonitor {
  enum Error: Swift.Error, LocalizedError {
    case failedToRegisterForEventNotifications(eventType: CGSEventType, code: CGError)

    var errorDescription: String? {
      switch self {
      case .failedToRegisterForEventNotifications(let eventType, let code):
        "Failed to register for \(eventType) notifications (\(code))."
      }
    }
  }

  enum Event {
    case spacesChanged
    case activeScreenChanged
    case activeSpaceChanged(spaceID: SpaceID)
    case windowAdded(windowID: WindowID, spaceID: SpaceID)
    case windowRemoved(windowID: WindowID, spaceID: SpaceID)
  }

  private static let cgsNotifyProc: CGSNotifyProcPtr = { eventType, data, dataLength, userData in
    guard let event = CGSEventType(rawValue: eventType), let userData else {
      return
    }

    let observer = Unmanaged<SpaceMonitor>.fromOpaque(userData).takeUnretainedValue()

    guard let continuation = observer.continuation else {
      return
    }

    let data = data.map { Data(bytes: $0, count: Int(dataLength)) }

    Task {
      switch event {
      case .packagesStatusBarSpaceChanged:
        continuation.yield(.activeScreenChanged)

      case .spaceCurrentChanged:
        guard let data, data.count >= 8 else {
          return
        }

        let spaceID = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: SpaceID.self) }
        let isCurrentFlag = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt8.self) }

        guard isCurrentFlag != 0 else {
          return
        }

        continuation.yield(.activeSpaceChanged(spaceID: spaceID))

      case .spaceCreated, .spaceDestroyed:
        continuation.yield(.spacesChanged)

      case .spaceWindowCreated:
        guard let data, data.count >= 12 else {
          return
        }

        let spaceID = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: SpaceID.self) }
        let windowID = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: WindowID.self) }

        continuation.yield(.windowAdded(windowID: windowID, spaceID: spaceID))

      case .spaceWindowDestroyed:
        guard let data, data.count >= 12 else {
          return
        }

        let spaceID = data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: SpaceID.self) }
        let windowID = data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: WindowID.self) }

        continuation.yield(.windowRemoved(windowID: windowID, spaceID: spaceID))
      }
    }
  }

  private var observedEventTypes: [CGSEventType] = []
  private var continuation: AsyncStream<Event>.Continuation?

  init() throws {
    for eventType in CGSEventType.allCases {
      let result = CGSRegisterNotifyProc(
        Self.cgsNotifyProc, eventType.rawValue,
        Unmanaged.passUnretained(self).toOpaque()
      )

      guard result == .success else {
        stop()
        throw Error.failedToRegisterForEventNotifications(eventType: eventType, code: result)
      }

      self.observedEventTypes.append(eventType)
    }
  }

  deinit {
    stop()
  }

  func start() -> AsyncStream<Event> {
    if continuation != nil {
      stop()
    }

    let (stream, continuation) = AsyncStream.makeStream(of: Event.self)

    continuation.onTermination = { [weak self] _ in
      self?.stop()
    }

    self.continuation = continuation

    return stream
  }

  private func stop() {
    continuation?.finish()

    for eventType in observedEventTypes {
      CGSRemoveNotifyProc(Self.cgsNotifyProc, eventType.rawValue, Unmanaged.passUnretained(self).toOpaque())
    }

    self.observedEventTypes.removeAll()
    self.continuation = nil
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

  let spaceMonitor: SpaceMonitor
  let onWidthChanged: (CGFloat) -> Void

  @State private var displaySpaces: [DisplayIdentifier: [SpaceID]] = [:]
  @State private var runningApps: [pid_t: App] = [:]
  @State private var spaceWindows: [SpaceID: Set<Window>] = [:]
  @State private var activeDisplayIdentifier = NSScreen.main?.displayIdentifier
  @State private var activeSpaceIDs: [DisplayIdentifier: SpaceID] = [:]

  private var activeDisplaySpaces: [Space] {
    guard let activeDisplayIdentifier, let spacesOnDisplay = displaySpaces[activeDisplayIdentifier] else {
      return []
    }

    return spacesOnDisplay.map { spaceID in
      let isActive = spaceID == activeSpaceIDs[activeDisplayIdentifier]
      let windowsOnSpace = spaceWindows[spaceID] ?? []
      let processIdentifiers = Set(windowsOnSpace.compactMap { $0.processIdentifier })
      let apps = processIdentifiers.compactMap { runningApps[$0] }.sorted { $0.name.lexicographicallyPrecedes($1.name) }

      return Space(id: spaceID, isActive: isActive, apps: apps)
    }
  }

  var body: some View {
    HStack(spacing: 12) {
      ForEach(activeDisplaySpaces.enumerated(), id: \.element.id) { index, space in
        HStack(spacing: 6) {
          Text("\(index + 1)")
            .font(.subheadline)
            .fontWeight(space.isActive ? .medium : .regular)
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
        .opacity(space.isActive ? 1 : 0.45)
        .animation(.snappy(duration: 0.2), value: space.isActive)
      }
    }
    .padding(.horizontal, 14)
    .fixedSize()
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { newWidth in
      onWidthChanged(newWidth)
    }
    .task {
      let cgsConnectionID = CGSMainConnectionID()

      syncSpaces(cgsConnectionID: cgsConnectionID)
      syncWindows(cgsConnectionID: cgsConnectionID)

      await withDiscardingTaskGroup { group in
        group.addTask { await monitorSpaces(cgsConnectionID: cgsConnectionID) }
        group.addTask { await monitorAppTerminations() }
      }
    }
  }

  private func syncSpaces(cgsConnectionID: UInt32) {
    guard
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        cgsConnectionID,
        nil
      )?.takeRetainedValue() as? [[String: Any]]
    else {
      return
    }

    var newDisplaySpaces: [DisplayIdentifier: [SpaceID]] = [:]
    var newActiveSpaceIDs: [DisplayIdentifier: SpaceID] = [:]

    for displayInfo in managedDisplaySpaces {
      guard
        let displayIdentifier = displayInfo["Display Identifier"] as? String,
        let spacesInfo = displayInfo["Spaces"] as? [[String: Any]]
      else {
        continue
      }

      newDisplaySpaces[displayIdentifier] = spacesInfo.compactMap { ($0["id64"] as? NSNumber)?.uint64Value }

      if let activeSpaceInfo = displayInfo["Current Space"] as? [String: Any],
        let activeSpaceID = (activeSpaceInfo["id64"] as? NSNumber)?.uint64Value
      {
        newActiveSpaceIDs[displayIdentifier] = activeSpaceID
      }
    }

    self.displaySpaces = newDisplaySpaces
    self.activeSpaceIDs = newActiveSpaceIDs
  }

  private func syncWindows(cgsConnectionID: UInt32) {
    guard
      let windowsInfo = CGWindowListCopyWindowInfo(
        [.optionAll, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return
    }

    self.spaceWindows.removeAll()

    for windowInfo in windowsInfo {
      guard
        let windowID = (windowInfo[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
        let spacesForWindow = CGSCopySpacesForWindows(
          cgsConnectionID,
          CGSSpaceMask.allSpaces.rawValue,
          [windowID] as CFArray
        )?.takeRetainedValue() as? [NSNumber],
        spacesForWindow.count == 1,
        let spaceID = spacesForWindow.first?.uint64Value,
        let window = Window(windowInfo: windowInfo, spaceID: spaceID)
      else {
        continue
      }

      addWindow(window, to: spaceID)
    }
  }

  private func monitorSpaces(cgsConnectionID: UInt32) async {
    for await event in spaceMonitor.start() {
      switch event {
      case .spacesChanged: syncSpaces(cgsConnectionID: cgsConnectionID)
      case .activeScreenChanged: self.activeDisplayIdentifier = NSScreen.main?.displayIdentifier
      case .activeSpaceChanged(let spaceID): handleActiveSpaceChanged(spaceID: spaceID)
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
    }
  }

  private func handleActiveSpaceChanged(spaceID: SpaceID) {
    guard let displayIdentifier = displaySpaces.first(where: { $0.value.contains(spaceID) })?.key else {
      return
    }

    self.activeSpaceIDs[displayIdentifier] = spaceID
  }

  private func handleWindowAdded(windowID: WindowID, spaceID: SpaceID) {
    guard
      let windowsInfo = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
      let windowInfo = windowsInfo.first,
      let window = Window(windowInfo: windowInfo, spaceID: spaceID)
    else {
      return
    }

    addWindow(window, to: spaceID)
  }

  private func handleWindowRemoved(windowID: WindowID, spaceID: SpaceID) {
    guard
      let windowsOnSpace = spaceWindows[spaceID],
      let window = windowsOnSpace.first(where: { $0.id == windowID })
    else {
      return
    }

    self.spaceWindows[spaceID]?.remove(window)
  }

  private func addWindow(_ window: Window, to spaceID: SpaceID) {
    self.spaceWindows[spaceID, default: []].insert(window)

    if runningApps[window.processIdentifier] == nil, let app = App(processIdentifier: window.processIdentifier) {
      self.runningApps[app.id] = app
    }
  }
}

@MainActor
final class StatusItemManager {
  private var statusItem: NSStatusItem?
  private var hostingView: NSHostingView<SpaceIndicatorView>?
  private var lastReportedWidth: CGFloat = .zero

  init(spaceMonitor: SpaceMonitor) {
    let spaceIndicatorView = SpaceIndicatorView(
      spaceMonitor: spaceMonitor,
      onWidthChanged: { [weak self] width in
        self?.setStatusItemWidth(to: width)
      }
    )
    let hostingView = NSHostingView(rootView: spaceIndicatorView)

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    statusItem.button?.isEnabled = false
    statusItem.button?.addSubview(hostingView)
    statusItem.behavior = .terminationOnRemoval

    self.statusItem = statusItem
    self.hostingView = hostingView
  }

  private func setStatusItemVisibility(to isVisible: Bool) {
    guard let statusItem, statusItem.isVisible != isVisible else {
      return
    }

    statusItem.isVisible = isVisible
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
  private let singletonLock: SingleInstanceLock
  private var spaceMonitor: SpaceMonitor?
  private var statusItemManager: StatusItemManager?

  init(singletonLock: SingleInstanceLock) {
    self.singletonLock = singletonLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let spaceMonitor = try SpaceMonitor()
      let statusItemManager = StatusItemManager(spaceMonitor: spaceMonitor)

      self.spaceMonitor = spaceMonitor
      self.statusItemManager = statusItemManager
    } catch {
      FileHandle.standardError.write(Data("Failed to initialize SpaceMonitor: \(error.localizedDescription)\n".utf8))
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
    case "quit": NSApplication.shared.terminate(nil)
    default: return
    }
  }
}

do {
  try MainActor.assumeIsolated {
    let singletonLock = try SingleInstanceLock()
    let delegate = AppDelegate(singletonLock: singletonLock)
    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.delegate = delegate
    application.run()
  }

} catch SingleInstanceLock.Error.instanceAlreadyRunning {
  let arguments = Array(CommandLine.arguments.dropFirst())

  guard !arguments.isEmpty else {
    print("Already running, specify \"quit\" to stop.")
    exit(0)
  }

  Command(arguments: arguments).send()
  exit(0)

} catch {
  FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
