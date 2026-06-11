import SwiftUI
import System
import UniformTypeIdentifiers

enum Configuration {
  static let subsystem = "industries.britown.SpaceIndicator"
}

struct FileDescriptorOutputStream: TextOutputStream {
  static var standardError = FileDescriptorOutputStream(.standardError)
  static var standardOutput = FileDescriptorOutputStream(.standardOutput)

  let fileDescriptor: FileDescriptor
  var errorHandler: ((any Error) -> Void)?

  init(_ fileDescriptor: FileDescriptor, errorHandler: ((any Error) -> Void)? = nil) {
    self.fileDescriptor = fileDescriptor
    self.errorHandler = errorHandler
  }

  mutating func write(_ string: String) {
    do {
      try fileDescriptor.writeAll(string.utf8)
    } catch {
      errorHandler?(error)
    }
  }
}

final class SingleInstanceLock {
  enum Error: Swift.Error, CustomStringConvertible {
    case instanceAlreadyRunning
    case failedToAcquireLock(underlyingError: Errno)

    var description: String {
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
      print("Failed to close lock file descriptor: \(error)", to: &FileDescriptorOutputStream.standardError)
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

extension CGError: @retroactive CustomStringConvertible {
  public var description: String {
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

    return "\(message) (\(self.rawValue))"
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
  enum Error: Swift.Error, CustomStringConvertible {
    case failedToRegisterForNotifications(eventType: CGSEventType, underlyingError: CGError)

    var description: String {
      switch self {
      case .failedToRegisterForNotifications(let eventType, let underlyingError):
        "Failed to register for '\(eventType)' notifications: \(underlyingError)"
      }
    }
  }

  enum Event {
    case spacesChanged
    case mainScreenChanged
    case currentSpaceChanged(spaceID: SpaceID)
    case windowAdded(windowID: CGWindowID, spaceID: SpaceID)
    case windowRemoved(windowID: CGWindowID, spaceID: SpaceID)
  }

  private let cgsNotifyProc: CGSNotifyProc = { eventType, data, dataLength, context in
    guard let event = CGSEventType(rawValue: eventType), let context else {
      return
    }

    Unmanaged<SpaceMonitor>.fromOpaque(context).takeUnretainedValue().handleEvent(
      event,
      data: data,
      dataLength: dataLength
    )
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

    case .spaceCreated, .spaceDestroyed:
      continuation.yield(.spacesChanged)

    case .spaceCurrentChanged:
      guard let data, dataLength >= MemoryLayout<SpaceID>.size + MemoryLayout<UInt8>.size else {
        return
      }

      let spaceID = data.load(as: SpaceID.self)
      let isCurrentFlag = data.load(fromByteOffset: MemoryLayout<SpaceID>.size, as: UInt8.self)

      guard isCurrentFlag != 0 else {
        return
      }

      continuation.yield(.currentSpaceChanged(spaceID: spaceID))
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

  @State private var cgsConnectionID = CGSMainConnectionID()
  @State private var displaySpaces: [DisplayIdentifier: [SpaceID]] = [:]
  @State private var runningApps: [pid_t: App] = [:]
  @State private var spaceWindows: [SpaceID: Set<Window>] = [:]
  @State private var mainScreenDisplayIdentifier = NSScreen.main?.displayIdentifier
  @State private var currentSpaceIDs: [DisplayIdentifier: SpaceID] = [:]
  @State private var spacesChangedEpoch: UInt64 = 0
  @State private var isRefreshPending = true

  private var mainScreenSpaces: [Space] {
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

  var body: some View {
    HStack(spacing: 12) {
      ForEach(mainScreenSpaces.enumerated(), id: \.element.id) { index, space in
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
    .task(id: spacesChangedEpoch) {
      self.isRefreshPending = true

      try? await Task.sleep(for: .milliseconds(100))

      guard !Task.isCancelled else {
        return
      }

      refreshSpaces()
      refreshWindows()

      self.isRefreshPending = false
    }
    .task {
      await withDiscardingTaskGroup { group in
        group.addTask { await monitorSpaces() }
        group.addTask { await monitorAppTerminations() }
      }
    }
  }

  private func refreshSpaces() {
    guard
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        cgsConnectionID,
        nil
      )?.takeRetainedValue() as? [[String: Any]]
    else {
      return
    }

    var displaySpaces: [DisplayIdentifier: [SpaceID]] = [:]
    var currentSpaceIDs: [DisplayIdentifier: SpaceID] = [:]

    for displayInfo in managedDisplaySpaces {
      guard
        let displayIdentifier = displayInfo["Display Identifier"] as? String,
        let spacesInfo = displayInfo["Spaces"] as? [[String: Any]]
      else {
        continue
      }

      displaySpaces[displayIdentifier] = spacesInfo.compactMap { $0["id64"] as? SpaceID }

      if let currentSpaceInfo = displayInfo["Current Space"] as? [String: Any],
        let currentSpaceID = currentSpaceInfo["id64"] as? SpaceID
      {
        currentSpaceIDs[displayIdentifier] = currentSpaceID
      }
    }

    self.displaySpaces = displaySpaces
    self.currentSpaceIDs = currentSpaceIDs
  }

  private func refreshWindows() {
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
      guard let window = Window(info: windowInfo, cgsConnectionID: cgsConnectionID) else {
        continue
      }

      trackWindow(window)
    }
  }

  private func monitorSpaces() async {
    for await event in spaceMonitor.events() {
      switch event {
      case .spacesChanged: self.spacesChangedEpoch += 1
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

@MainActor
final class StatusItemManager {
  private static let autosaveName = "SpaceIndicator"
  private static let preferredPositionKey = "NSStatusItem Preferred Position \(autosaveName)"

  private var hostingView: NSHostingView<SpaceIndicatorView>?
  private var statusItem: NSStatusItem?
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
    statusItem.autosaveName = Self.autosaveName
    statusItem.behavior = .terminationOnRemoval
    statusItem.button?.isEnabled = false
    statusItem.button?.addSubview(hostingView)

    self.hostingView = hostingView
    self.statusItem = statusItem
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
  private let singleInstanceLock: SingleInstanceLock
  private var spaceMonitor: SpaceMonitor?
  private var statusItemManager: StatusItemManager?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let spaceMonitor = try SpaceMonitor()
      let statusItemManager = StatusItemManager(spaceMonitor: spaceMonitor)

      self.spaceMonitor = spaceMonitor
      self.statusItemManager = statusItemManager
    } catch {
      print(error, to: &FileDescriptorOutputStream.standardError)
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
    case .printLog: break
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

    if isatty(STDOUT_FILENO) == 0 {
      do {
        let fd = try FileDescriptor.open(
          FilePath(
            FileManager.default.temporaryDirectory.appendingPathComponent("\(Configuration.subsystem).log").path
          ),
          .writeOnly,
          options: [.create, .truncate],
          permissions: [.ownerReadWrite, .groupRead, .otherRead]
        )

        try fd.closeAfter {
          _ = try fd.duplicate(as: .standardOutput)
          _ = try fd.duplicate(as: .standardError)
        }

        setvbuf(stdout, nil, _IONBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
      } catch {
        print("Failed to redirect output: \(error)", to: &FileDescriptorOutputStream.standardError)
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
    print("Already running.\n\n\(usageDescription)", to: &FileDescriptorOutputStream.standardError)
    exit(EX_USAGE)
  }

  guard arguments.dropFirst().isEmpty else {
    print("Too many arguments.\n\n\(usageDescription)", to: &FileDescriptorOutputStream.standardError)
    exit(EX_USAGE)
  }

  guard let ipcCommand = IPCCommand(rawValue: argument.lowercased()) else {
    print("Unknown command.\n\n\(usageDescription)", to: &FileDescriptorOutputStream.standardError)
    exit(EX_USAGE)
  }

  if case .printLog = ipcCommand {
    let logFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(Configuration.subsystem).log")

    guard FileManager.default.fileExists(atPath: logFileURL.path) else {
      print("Log file does not exist.", to: &FileDescriptorOutputStream.standardError)
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
      print("Failed to read log file: \(error)", to: &FileDescriptorOutputStream.standardError)
      exit(EXIT_FAILURE)
    }
  } else {
    ipcCommand.send()
  }

  exit(EXIT_SUCCESS)

} catch {
  print(error, to: &FileDescriptorOutputStream.standardError)
  exit(EXIT_FAILURE)
}
