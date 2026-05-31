import AppKit

enum Configuration {
  static let subsystem = "industries.britown.FloatingMenuBar"
  static let modifierKey = CGEventFlags.maskCommand
}

extension AXUIElement {
  var children: [AXUIElement]? {
    var valuesRef: CFArray?
    return AXUIElementCopyAttributeValues(
      self,
      NSAccessibility.Attribute.children.rawValue as CFString,
      0,
      Int.max,
      &valuesRef
    ) == .success
      ? valuesRef as? [AXUIElement]
      : nil
  }

  static func element(for pid: pid_t) -> AXUIElement {
    return AXUIElementCreateApplication(pid)
  }

  func value<T>(for attribute: NSAccessibility.Attribute, as type: T.Type = T.self) -> T? {
    var rawValue: CFTypeRef?
    return
      AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &rawValue) == .success
      ? rawValue as? T
      : nil
  }

  func values(for attributes: [NSAccessibility.Attribute]) -> [NSAccessibility.Attribute: Any]? {
    var rawValues: CFArray?
    return AXUIElementCopyMultipleAttributeValues(
      self,
      attributes.map { $0.rawValue as CFString } as CFArray,
      AXCopyMultipleAttributeOptions(rawValue: 0),
      &rawValues
    ) == .success
      ? (rawValues as? [AnyObject]).map { Dictionary(uniqueKeysWithValues: zip(attributes, $0)) }
      : nil
  }

  @discardableResult
  func performAction(_ action: NSAccessibility.Action) -> AXError {
    return AXUIElementPerformAction(self, action.rawValue as CFString)
  }
}

extension NSAccessibility.Attribute {
  static let menuItemCommandCharacter = Self(rawValue: "AXMenuItemCmdChar")
  static let menuItemMarkCharacter = Self(rawValue: "AXMenuItemMarkChar")
  static let menuItemCommandModifiers = Self(rawValue: "AXMenuItemCmdModifiers")
}

extension NSEvent.ModifierFlags {
  init(fromAXCommandModifiers axModifiers: UInt32?) {
    self = []

    guard let axModifiers else {
      return
    }

    if (axModifiers & AXMenuItemModifiers.shift.rawValue) != 0 {
      self.insert(.shift)
    }

    if (axModifiers & AXMenuItemModifiers.option.rawValue) != 0 {
      self.insert(.option)
    }

    if (axModifiers & AXMenuItemModifiers.control.rawValue) != 0 {
      self.insert(.control)
    }

    if (axModifiers & AXMenuItemModifiers.noCommand.rawValue) == 0 {
      self.insert(.command)
    }
  }
}

extension NSFont {
  static func boldSystemFont(ofSize size: CGFloat) -> NSFont {
    return NSFontManager.shared.convert(NSFont.systemFont(ofSize: size), toHaveTrait: .boldFontMask)
  }
}

@MainActor
final class AppMenu {
  private struct MenuItemData {
    let title: String
    let isEnabled: Bool
    let markCharacter: String?
    let commandCharacter: String?
    let commandModifiers: UInt32?
    let children: [AXUIElement]?
  }

  static func popUp(at location: NSPoint) throws {
    guard let appMenu = buildAppMenu() else {
      return
    }

    appMenu.popUp(positioning: nil, at: location, in: nil)
  }

  private static func buildAppMenu() -> NSMenu? {
    guard
      AXIsProcessTrustedWithOptions(nil),
      let activeApp = NSWorkspace.shared.menuBarOwningApplication,
      let menuBarElement = AXUIElement.element(for: activeApp.processIdentifier).value(for: .menuBar) as AXUIElement?
    else {
      return nil
    }

    let appMenu = buildMenu(from: menuBarElement)

    if let mainAppMenuItem = appMenu?.items.first {
      mainAppMenuItem.attributedTitle = NSAttributedString(
        string: mainAppMenuItem.title,
        attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
      )
    }

    return appMenu
  }

  private static func buildMenu(from element: AXUIElement, isSubmenu: Bool = false) -> NSMenu? {
    guard let menuItemElements = element.children, !menuItemElements.isEmpty else {
      return nil
    }

    var menuItems: [NSMenuItem] = []
    menuItems.reserveCapacity(menuItemElements.count)

    for menuItemElement in menuItemElements {
      guard
        let menuItemData = extractMenuItemData(from: menuItemElement),
        menuItemData.title != "Apple",
        let menuItem = buildMenuItem(from: menuItemData, element: menuItemElement, previousItem: menuItems.last)
      else {
        continue
      }

      menuItems.append(menuItem)
    }

    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.minimumWidth = 160.0
    menu.items = menuItems

    return menu
  }

  private static func extractMenuItemData(from element: AXUIElement) -> MenuItemData? {
    guard
      let axAttributeValues = element.values(for: [
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
      markCharacter: axAttributeValues[.menuItemMarkCharacter] as? String,
      commandCharacter: axAttributeValues[.menuItemCommandCharacter] as? String,
      commandModifiers: axAttributeValues[.menuItemCommandModifiers] as? UInt32,
      children: axAttributeValues[.children] as? [AXUIElement]
    )
  }

  private static func buildMenuItem(
    from menuItemData: MenuItemData,
    element: AXUIElement,
    previousItem: NSMenuItem?
  ) -> NSMenuItem? {
    if menuItemData.title.isEmpty {
      return NSMenuItem.separator()
    }

    let keyEquivalent = menuItemData.commandCharacter?.lowercased() ?? ""
    let keyEquivalentModifierMask =
      keyEquivalent.isEmpty
      ? []
      : NSEvent.ModifierFlags(fromAXCommandModifiers: menuItemData.commandModifiers)

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
    menuItem.state =
      switch menuItemData.markCharacter {
      case "✓": .on
      case "-": .mixed
      default: .off
      }

    if let submenuElement = menuItemData.children?.first {
      menuItem.submenu = buildMenu(from: submenuElement, isSubmenu: true)
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

    let menuItemElement = representedObject as! AXUIElement

    DispatchQueue.main.async {
      menuItemElement.performAction(.press)
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
      FileHandle.standardError.write(Data("Accessibility permission not granted.\n".utf8))
      exit(EXIT_FAILURE)
    }

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
      ),
      let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
    else {
      FileHandle.standardError.write(Data("Failed to create event tap.\n".utf8))
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
      try? AppMenu.popUp(at: NSEvent.mouseLocation)
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
