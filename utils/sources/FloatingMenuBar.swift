// Shared: Accessibility Agent CGEventFlags EventTap Log

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.FloatingMenuBar"
  static let modifierKey = CGEventFlags.maskCommand
  static let submenuImageTopLevelTitles: [String: Set<String>] = [
    "com.google.Chrome": ["Bookmarks"]
  ]
  static let minimumMenuWidth: CGFloat = 160.0
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
  enum Error: Swift.Error, LocalizedError {
    case failedToRetrieveMenuBarElement(application: NSRunningApplication, underlyingError: any Swift.Error)
    case failedToBuildMenu(application: NSRunningApplication, underlyingError: any Swift.Error)

    var errorDescription: String? {
      switch self {
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
    try AccessibilityPermission.ensureGranted()

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
        let appMenu = try buildMenu(
          from: menuBarElement,
          skipFirstChild: true,
          submenuImageTopLevelTitles: Configuration.submenuImageTopLevelTitles[
            application.bundleIdentifier ?? "",
            default: []
          ],
          showsSubmenuImages: false,
          minimumWidth: minimumWidth
        ),
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
    submenuImageTopLevelTitles: Set<String>,
    showsSubmenuImages: Bool,
    minimumWidth: CGFloat?
  ) throws -> NSMenu? {
    var menuItemElements = try element.children()

    guard !menuItemElements.isEmpty else {
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
          submenuImageTopLevelTitles: submenuImageTopLevelTitles,
          showsSubmenuImages: showsSubmenuImages,
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
    submenuImageTopLevelTitles: Set<String>,
    showsSubmenuImages: Bool,
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
      if showsSubmenuImages {
        menuItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menuItem.preferredImageVisibility = .visible
      }

      menuItem.submenu = try buildMenu(
        from: submenuElement,
        submenuImageTopLevelTitles: submenuImageTopLevelTitles,
        showsSubmenuImages: showsSubmenuImages || submenuImageTopLevelTitles.contains(menuItemData.title),
        minimumWidth: minimumWidth
      )
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
        Log.error(error.localizedDescription)
      }
    }
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private let startDate = Date.now
  private var eventTap: EventTap?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      let eventTap = try EventTap(location: .cgSessionEventTap, eventTypes: [.rightMouseDown])
      eventTap.eventHandler = { [weak self] event in self?.handleEvent(event) ?? false }
      eventTap.isEnabled = true

      self.eventTap = eventTap
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }

    AXUIElement.setGlobalMessagingTimeout(seconds: 1.0)
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.eventTap = nil
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AccessibilityPermission.isGranted)
        Event tap active: \(eventTap.map { "\($0.isActive)" } ?? "<none>")
      """
    )
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    switch event.type {
    case .rightMouseDown where event.flags.intersection(CGEventFlags.modifierFlagsMask) == Configuration.modifierKey:
      do {
        try AppMenu.popUp(at: NSEvent.mouseLocation, minimumWidth: Configuration.minimumMenuWidth)
      } catch {
        Log.error(error.localizedDescription)
      }

      return true

    default:
      return false
    }
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .printLog: logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case printLog = "print-log"
  case quit
}

@main
enum FloatingMenuBar {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
