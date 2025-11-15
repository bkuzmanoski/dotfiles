import AppKit

enum Constants {
  static let subsystem = "industries.britown.FloatingMenuBar"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let modifierKey = CGEventFlags.maskCommand
  static let minimumWidth: CGFloat = 160.0
}

enum Signal {
  enum Error: Swift.Error, LocalizedError {
    case interrupted(CInt)

    var errorDescription: String? {
      switch self {
      case .interrupted(let signal): "Interrupted with signal \(Signal.name(for: signal))"
      }
    }
  }

  static func name(for signal: CInt) -> String {
    guard let namePointer = strsignal(signal) else {
      return "Unknown signal (\(signal))"
    }

    return String(cString: namePointer)
  }

  static func stream(for signals: [CInt]) -> AsyncStream<CInt> {
    return AsyncStream { continuation in
      let sources = signals.map { signal in
        DispatchSource.makeSignalSource(signal: signal, queue: .main)
      }

      for (signal, source) in zip(signals, sources) {
        source.setEventHandler { continuation.yield(signal) }
        source.resume()
      }

      continuation.onTermination = { @Sendable _ in
        sources.forEach { $0.cancel() }
      }
    }
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

class SingletonLock {
  enum Error: Swift.Error, LocalizedError {
    case instanceAlreadyRunning
    case failedToAcquireLock(String)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: "Instance already running."
      case .failedToAcquireLock(let message): "Failed to acquire lock: \(message)"
      }
    }
  }

  private let lockFilePath = NSTemporaryDirectory().appending(Constants.lockFileName)
  private var lockFileDescriptor: CInt

  init() throws {
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)

    if fd == -1 {
      throw Error.failedToAcquireLock(String(cString: strerror(errno)))
    }

    if flock(fd, LOCK_EX | LOCK_NB) == -1 {
      close(fd)

      guard errno == EWOULDBLOCK else {
        throw Error.failedToAcquireLock("Failed to acquire lock: \(String(cString: strerror(errno)))")
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

extension AXUIElement {
  static var systemWideElement: AXUIElement { AXUIElementCreateSystemWide() }

  var children: [AXUIElement]? {
    var valuesRef: CFArray?

    guard
      AXUIElementCopyAttributeValues(
        self,
        NSAccessibility.Attribute.children.rawValue as CFString,
        0,
        Int.max,
        &valuesRef
      ) == .success
    else {
      return nil
    }

    return valuesRef as? [AXUIElement]
  }

  static func element(for pid: pid_t) -> AXUIElement {
    return AXUIElementCreateApplication(pid)
  }

  func value<T>(for attribute: NSAccessibility.Attribute) -> T? {
    var rawValue: CFTypeRef?

    guard
      AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &rawValue) == .success,
      let rawValue
    else {
      return nil
    }

    return rawValue as? T
  }

  func values(for attributes: [NSAccessibility.Attribute]) -> [NSAccessibility.Attribute: Any]? {
    var rawValues: CFArray?

    guard
      AXUIElementCopyMultipleAttributeValues(
        self,
        attributes.map { $0.rawValue as CFString } as CFArray,
        AXCopyMultipleAttributeOptions(rawValue: 0),
        &rawValues
      ) == .success,
      let rawValues
    else {
      return nil
    }

    return Dictionary(uniqueKeysWithValues: zip(attributes, rawValues as [AnyObject]).map { ($0, $1) })
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

class AppMenu {
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
    menu.minimumWidth = Constants.minimumWidth
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

class AppDelegate: NSObject, NSApplicationDelegate {
  var eventTap: CFMachPort?

  private var singletonLock: SingletonLock
  private var runLoopSource: CFRunLoopSource?

  init(singletonLock: SingletonLock) {
    self.singletonLock = singletonLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard AXIsProcessTrustedWithOptions(nil) else {
      FileHandle.standardError.write(Data("Error: Accessibility permission denied.\n".utf8))
      NSApplication.shared.terminate(nil)
      return
    }

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: 1 << CGEventType.rightMouseDown.rawValue,
        callback: eventTapCallback,
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      FileHandle.standardError.write(Data("Error: Failed to create event tap.\n".utf8))
      NSApplication.shared.terminate(nil)
      return
    }

    self.eventTap = eventTap
    self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    observeSignals()
    observeCommands()
  }

  func applicationWillTerminate(_ notification: Notification) {
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)

      if let runLoopSource {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      }

      CFMachPortInvalidate(eventTap)
    }
  }

  private func observeSignals() {
    Task {
      for await _ in Signal.stream(for: [SIGHUP, SIGINT, SIGTERM]) {
        await NSApplication.shared.terminate(nil)
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

        await handleCommand(with: arguments)
      }
    }
  }

  private func handleCommand(with arguments: [String]) async {
    guard let command = arguments.first else {
      return
    }

    switch command {
    case "quit": await NSApplication.shared.terminate(nil)
    default: return
    }
  }
}

func eventTapCallback(
  proxy: CGEventTapProxy,
  type: CGEventType,
  event: CGEvent,
  refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
  guard let refcon else {
    return Unmanaged.passUnretained(event)
  }

  guard type != .tapDisabledByTimeout else {
    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(refcon).takeUnretainedValue()

    if let eventTap = appDelegate.eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    return Unmanaged.passUnretained(event)
  }

  guard CGEventSource.flagsState(.hidSystemState).contains(Constants.modifierKey) else {
    return Unmanaged.passUnretained(event)
  }

  try? AppMenu.popUp(at: NSEvent.mouseLocation)
  return nil
}

do {
  let singletonLock = try SingletonLock()
  let delegate = AppDelegate(singletonLock: singletonLock)
  let application = NSApplication.shared
  application.delegate = delegate
  application.run()
} catch SingletonLock.Error.instanceAlreadyRunning {
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
