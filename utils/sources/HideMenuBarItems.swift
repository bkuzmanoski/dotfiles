// Shared: Agent Log NSStatusItem

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.HideMenuBarItems"
}

@MainActor
final class MenuBarItemManager {
  private static let menuBarPreferencesPath = URL.homeDirectory.appending(
    path: "Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist"
  ).path(percentEncoded: false)

  private let startDate = Date.now
  private let boundaryStatusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var spacerStatusItems: [NSStatusItem] = []
  private var screenParametersObservationTask: Task<Void, Never>?

  private var isHidingItems: Bool { boundaryStatusItem.length != NSStatusItem.variableLength }

  init() {
    boundaryStatusItem.behavior = .terminationOnRemoval
    boundaryStatusItem.button?.isEnabled = false

    self.screenParametersObservationTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: NSApplication.didChangeScreenParametersNotification
      ) {
        guard let self = self else {
          break
        }

        guard isHidingItems else {
          return
        }

        hideItems()
      }
    }
  }

  isolated deinit {
    NSStatusBar.system.removeStatusItem(boundaryStatusItem)
    removeSpacerStatusItems()
    screenParametersObservationTask?.cancel()
  }

  func showItems() {
    boundaryStatusItem.length = NSStatusItem.variableLength
    boundaryStatusItem.button?.title = "􂉏"

    removeSpacerStatusItems()
  }

  func hideItems() {
    let screenWidths = NSScreen.screens.map(\.frame.width)
    let maximumSpacerStatusItemLength = ((screenWidths.min() ?? 0) / 2).rounded(.down)

    guard maximumSpacerStatusItemLength > 0 else {
      return
    }

    let spacerStatusItemCount = max(
      Int(((screenWidths.max() ?? 0) / maximumSpacerStatusItemLength).rounded(.up)) - 1,
      1
    )

    if spacerStatusItems.count != spacerStatusItemCount {
      removeSpacerStatusItems()
      addSpacerStatusItems(count: spacerStatusItemCount)
    }

    boundaryStatusItem.button?.title = ""

    for statusItem in [boundaryStatusItem] + spacerStatusItems {
      setLength(of: statusItem, to: maximumSpacerStatusItemLength)
    }
  }

  func toggleItemVisibility() {
    isHidingItems ? showItems() : hideItems()
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Menu Bar items hidden: \(isHidingItems)
        Boundary status item visible: \(boundaryStatusItem.isVisible)
        Boundary status item length: \(boundaryStatusItem.length)
        Boundary status item window width: \(boundaryStatusItem.button?.window?.frame.width ?? 0)
        Boundary status item MenuBarAgent position: \(menuBarAgentPosition(of: boundaryStatusItem).map { "\($0)" } ?? "<none>")
        Spacer status items: \(spacerStatusItems.map { "\($0.autosaveName ?? "<none>") (\($0.button?.window?.frame.width ?? 0))" }.joined(separator: ", "))
      """
    )
  }

  private func setLength(of statusItem: NSStatusItem, to length: CGFloat) {
    statusItem.length = length

    if let windowWidth = statusItem.button?.window?.frame.width, windowWidth > length {
      statusItem.length -= windowWidth - length
    }
  }

  private func menuBarAgentPosition(of item: NSStatusItem) -> Double? {
    guard
      let autosaveName = item.autosaveName,
      let data = FileManager.default.contents(atPath: Self.menuBarPreferencesPath),
      let preferences = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let positions = preferences["TrailingItemPreferredPositions"] as? [String: Double]
    else {
      return nil
    }

    return positions["status:\(ProcessInfo.processInfo.processName)::\(autosaveName)"]
  }

  private func addSpacerStatusItems(count: Int) {
    guard spacerStatusItems.isEmpty else {
      return
    }

    guard let boundaryStatusItemPosition = menuBarAgentPosition(of: boundaryStatusItem) else {
      Log.error("Failed to read the boundary status item's MenuBarAgent position, skipping spacer status items.")
      return
    }

    for index in 0..<count {
      let autosaveName = "Spacer-\(Int(boundaryStatusItemPosition))-\(index)"

      UserDefaults.standard.set(
        boundaryStatusItemPosition + Double(index + 1) * 0.1,
        forKey: NSStatusItem.preferredPositionKey(for: autosaveName)
      )

      let spacerItem = NSStatusBar.system.statusItem(withLength: 1)
      spacerItem.autosaveName = autosaveName
      spacerItem.behavior = .terminationOnRemoval
      spacerItem.button?.isEnabled = false

      self.spacerStatusItems.append(spacerItem)
    }
  }

  private func removeSpacerStatusItems() {
    for spacerItem in spacerStatusItems {
      NSStatusBar.system.removeStatusItem(spacerItem)
    }

    self.spacerStatusItems.removeAll()
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var menuBarItemManager: MenuBarItemManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    self.menuBarItemManager = MenuBarItemManager()

    menuBarItemManager?.hideItems()
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.menuBarItemManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .toggle: menuBarItemManager?.toggleItemVisibility()
    case .printLog: menuBarItemManager?.logDiagnosticReport()
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
enum HideMenuBarItems {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .accessory) {
      AppDelegate()
    }
  }
}
