import AppKit
import System

enum Configuration {
  static let subsystem = "industries.britown.FloatingMenuBar"
  static let minimumMenuWidth: CGFloat = 160.0
  static let modifierKey = CGEventFlags.maskCommand
}

struct FileDescriptorOutputStream: TextOutputStream {
  static var standardError = FileDescriptorOutputStream(.standardError)
  static var standardOutput = FileDescriptorOutputStream(.standardOutput)

  let fileDescriptor: FileDescriptor
  var errorHandler: ((Error) -> Void)?

  init(_ fileDescriptor: FileDescriptor, errorHandler: ((Error) -> Void)? = nil) {
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

extension AXUIElement {
  enum Error: Swift.Error, CustomStringConvertible {
    case typeMismatch

    var description: String {
      switch self {
      case .typeMismatch: "Returned value type does not match expected type."
      }
    }
  }

  static let systemWideElement = AXUIElementCreateSystemWide()

  static func setGlobalMessagingTimeout(seconds timeoutInSeconds: Float) {
    AXUIElementSetMessagingTimeout(systemWideElement, timeoutInSeconds)
  }

  func children() throws -> [AXUIElement]? {
    var valuesRef: CFArray?

    try AXUIElementCopyAttributeValues(
      self,
      NSAccessibility.Attribute.children.rawValue as CFString,
      0,
      Int.max,
      &valuesRef
    ).throwIfFailed()

    return valuesRef as? [AXUIElement]
  }

  static func element(for pid: pid_t) -> AXUIElement {
    return AXUIElementCreateApplication(pid)
  }

  func value<T>(for attribute: NSAccessibility.Attribute, as type: T.Type = T.self) throws -> T {
    var rawValue: CFTypeRef?

    try AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &rawValue).throwIfFailed()

    guard let value = rawValue as? T else {
      throw Error.typeMismatch
    }

    return value
  }

  func values(for attributes: [NSAccessibility.Attribute]) throws -> [NSAccessibility.Attribute: Any]? {
    var rawValues: CFArray?

    try AXUIElementCopyMultipleAttributeValues(
      self,
      attributes.map { $0.rawValue as CFString } as CFArray,
      AXCopyMultipleAttributeOptions(rawValue: 0),
      &rawValues
    ).throwIfFailed()

    return (rawValues as? [AnyObject]).map { Dictionary(uniqueKeysWithValues: zip(attributes, $0)) }
  }

  func performAction(_ action: NSAccessibility.Action) throws {
    try AXUIElementPerformAction(self, action.rawValue as CFString).throwIfFailed()
  }
}

extension AXError: @retroactive _BridgedNSError, @retroactive Error, @retroactive CustomStringConvertible {
  public var description: String {
    let message: String

    switch (self) {
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

    return "\(message) (\(self.rawValue))"
  }
}

extension AXError {
  func throwIfFailed() throws {
    if self != .success {
      throw self
    }
  }
}

extension NSAccessibility.Attribute {
  static let menuItemCommandCharacter = NSAccessibility.Attribute(rawValue: kAXMenuItemCmdCharAttribute)
  static let menuItemCommandModifiers = NSAccessibility.Attribute(rawValue: kAXMenuItemCmdModifiersAttribute)
  static let menuItemMarkCharacter = NSAccessibility.Attribute(rawValue: kAXMenuItemMarkCharAttribute)
}

extension NSEvent.ModifierFlags {
  init(axMenuItemModifiers: AXMenuItemModifiers) {
    self.init(
      [
        axMenuItemModifiers.contains(.shift) ? .shift : nil,
        axMenuItemModifiers.contains(.option) ? .option : nil,
        axMenuItemModifiers.contains(.control) ? .control : nil,
        axMenuItemModifiers.contains(.noCommand) ? nil : .command
      ]
      .compactMap { $0 }
    )
  }
}

@MainActor
final class AppMenu {
  enum Error: Swift.Error, CustomStringConvertible {
    case accessibilityPermissionNotGranted
    case failedToRetrieveMenuBarElement(application: NSRunningApplication, underlyingError: Swift.Error)
    case failedToBuildMenu(application: NSRunningApplication, underlyingError: Swift.Error)

    var description: String {
      switch self {
      case .accessibilityPermissionNotGranted:
        "Accessibility permission not granted."

      case .failedToRetrieveMenuBarElement(let application, let underlyingError):
        "Failed to retrieve menu bar element for \(application.localizedName.map { "'\($0)'" } ?? "active application"): \(underlyingError)"

      case .failedToBuildMenu(let application, let underlyingError):
        "Failed to build menu for \(application.localizedName.map { "'\($0)'" } ?? "active application"): \(underlyingError)"
      }
    }
  }

  private static let appMenuFont = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)

  private struct MenuItemData {
    let title: String
    let isEnabled: Bool
    let commandCharacter: String?
    let commandModifiers: UInt32?
    let markCharacter: String?
    let children: [AXUIElement]?
  }

  static func popUp(at location: NSPoint, minimumWidth: CGFloat? = nil) throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    guard let application = NSWorkspace.shared.menuBarOwningApplication else {
      return
    }

    let menuBarElement: AXUIElement?

    do {
      menuBarElement = try AXUIElement.element(for: application.processIdentifier).value(for: .menuBar) as AXUIElement
    } catch {
      throw Error.failedToRetrieveMenuBarElement(application: application, underlyingError: error)
    }

    do {
      guard
        let menuBarElement,
        let appMenu = try buildMenu(from: menuBarElement, skipFirstChild: true, minimumWidth: minimumWidth),
        let mainAppMenuItem = appMenu.items.first
      else {
        return
      }

      mainAppMenuItem.attributedTitle = NSAttributedString(
        string: mainAppMenuItem.title,
        attributes: [.font: appMenuFont]
      )
      appMenu.popUp(positioning: nil, at: location, in: nil)
    } catch {
      throw Error.failedToBuildMenu(application: application, underlyingError: error)
    }
  }

  private static func buildMenu(
    from element: AXUIElement,
    skipFirstChild: Bool = false,
    isSubmenu: Bool = false,
    minimumWidth: CGFloat?
  ) throws -> NSMenu? {
    guard var menuItemElements = try element.children(), !menuItemElements.isEmpty else {
      return nil
    }

    if skipFirstChild {
      menuItemElements.removeFirst()
    }

    var menuItems: [NSMenuItem] = []
    menuItems.reserveCapacity(menuItemElements.count)

    for menuItemElement in menuItemElements {
      guard
        let menuItemData = try extractMenuItemData(from: menuItemElement),
        let menuItem = try buildMenuItem(
          from: menuItemData,
          element: menuItemElement,
          previousItem: menuItems.last,
          minimumWidth: minimumWidth
        )
      else {
        continue
      }

      menuItems.append(menuItem)
    }

    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.items = menuItems

    if let minimumWidth {
      menu.minimumWidth = minimumWidth
    }

    return menu
  }

  private static func extractMenuItemData(from element: AXUIElement) throws -> MenuItemData? {
    guard
      let axAttributeValues = try element.values(for: [
        .title,
        .role,
        .enabled,
        .menuItemMarkCharacter,
        .menuItemCommandCharacter,
        .menuItemCommandModifiers,
        .children
      ]),
      let title = axAttributeValues[.title] as? String,
      let role = axAttributeValues[.role] as? String,
      role == NSAccessibility.Role.menuBarItem.rawValue || role == NSAccessibility.Role.menuItem.rawValue
    else {
      return nil
    }

    return MenuItemData(
      title: title,
      isEnabled: axAttributeValues[.enabled] as? Bool ?? true,
      commandCharacter: axAttributeValues[.menuItemCommandCharacter] as? String,
      commandModifiers: axAttributeValues[.menuItemCommandModifiers] as? UInt32,
      markCharacter: axAttributeValues[.menuItemMarkCharacter] as? String,
      children: axAttributeValues[.children] as? [AXUIElement]
    )
  }

  private static func buildMenuItem(
    from menuItemData: MenuItemData,
    element: AXUIElement,
    previousItem: NSMenuItem?,
    minimumWidth: CGFloat?
  ) throws -> NSMenuItem? {
    if menuItemData.title.isEmpty {
      return NSMenuItem.separator()
    }

    let keyEquivalent = menuItemData.commandCharacter?.lowercased() ?? ""
    let keyEquivalentModifierMask =
      keyEquivalent.isEmpty
      ? []
      : NSEvent.ModifierFlags(axMenuItemModifiers: AXMenuItemModifiers(rawValue: menuItemData.commandModifiers ?? 0))

    if let previousItem,
      previousItem.title == menuItemData.title,
      previousItem.keyEquivalent == keyEquivalent,
      previousItem.keyEquivalentModifierMask == keyEquivalentModifierMask
    {
      return nil
    }

    let (isAlternate, keyEquivalentModifierMaskOverride) = determineIfAlternate(
      title: menuItemData.title,
      keyEquivalent: keyEquivalent,
      keyEquivalentModifierMask: keyEquivalentModifierMask,
      previousItem: previousItem
    )
    let menuItem = NSMenuItem(title: menuItemData.title, action: nil, keyEquivalent: "")
    menuItem.representedObject = element
    menuItem.isEnabled = menuItemData.isEnabled
    menuItem.keyEquivalent = keyEquivalent
    menuItem.keyEquivalentModifierMask = keyEquivalentModifierMaskOverride ?? keyEquivalentModifierMask
    menuItem.isAlternate = isAlternate

    switch menuItemData.markCharacter {
    case "✓": menuItem.state = .on
    case "-": menuItem.state = .mixed
    default: menuItem.state = .off
    }

    if let submenuElement = menuItemData.children?.first {
      menuItem.submenu = try buildMenu(from: submenuElement, isSubmenu: true, minimumWidth: minimumWidth)
    } else {
      menuItem.target = self
      menuItem.action = #selector(menuItemAction(_:))
    }

    return menuItem
  }

  private static func determineIfAlternate(
    title: String,
    keyEquivalent: String,
    keyEquivalentModifierMask: NSEvent.ModifierFlags,
    previousItem: NSMenuItem?
  ) -> (isAlternate: Bool, keyEquivalentModifierMaskOverride: NSEvent.ModifierFlags?) {
    guard
      keyEquivalent == previousItem?.keyEquivalent,
      let previousTitle = previousItem?.title,
      let previousKeyEquivalentModifierMask = previousItem?.keyEquivalentModifierMask
    else {
      return (false, nil)
    }

    if !previousKeyEquivalentModifierMask.isEmpty,
      keyEquivalentModifierMask.isSuperset(of: previousKeyEquivalentModifierMask)
    {
      return (true, nil)
    } else if title.hasPrefix(previousTitle) {
      return (true, .option)
    }

    return (false, nil)
  }

  @objc private static func menuItemAction(_ sender: NSMenuItem) {
    guard
      let representedObject = sender.representedObject,
      CFGetTypeID(representedObject as CFTypeRef) == AXUIElementGetTypeID()
    else {
      return
    }

    DispatchQueue.main.async {
      do {
        try (representedObject as! AXUIElement).performAction(.press)
      } catch {
        print(error, to: &FileDescriptorOutputStream.standardError)
      }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let singleInstanceLock: SingleInstanceLock
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init(singleInstanceLock: SingleInstanceLock) {
    self.singleInstanceLock = singleInstanceLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard AXIsProcessTrustedWithOptions(nil) else {
      print("Accessibility permission not granted.", to: &FileDescriptorOutputStream.standardError)
      exit(EXIT_FAILURE)
    }

    AXUIElement.setGlobalMessagingTimeout(seconds: 1.0)

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: 1 << CGEventType.rightMouseDown.rawValue,
        callback: { _, type, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }

          return
            Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue().handleEvent(ofType: type)
            ? nil
            : Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      print("Failed to create event tap.", to: &FileDescriptorOutputStream.standardError)
      exit(EXIT_FAILURE)
    }

    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
      CFMachPortInvalidate(eventTap)
      print("Failed to create run loop source for event tap.", to: &FileDescriptorOutputStream.standardError)
      exit(EXIT_FAILURE)
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    observeProcessSignals()
    observeIPCCommands()

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
  }

  func applicationWillTerminate(_ notification: Notification) {
    guard let eventTap, let runLoopSource else {
      return
    }

    CGEvent.tapEnable(tap: eventTap, enable: false)
    CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CFMachPortInvalidate(eventTap)
  }

  private func handleEvent(ofType type: CGEventType) -> Bool {
    switch type {
    case .rightMouseDown where CGEventSource.flagsState(.hidSystemState).contains(Configuration.modifierKey):
      do {
        try AppMenu.popUp(at: NSEvent.mouseLocation, minimumWidth: Configuration.minimumMenuWidth)
      } catch {
        print(error, to: &FileDescriptorOutputStream.standardError)
      }

      return true

    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }

      return false

    default:
      return false
    }
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
    case .printLog: break
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, CaseIterable {
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
    application.setActivationPolicy(.prohibited)
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
