// Shared: Agent FixedPointFormatStyle Log NSStatusItem

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.HideMenuBarItems"
}

@MainActor
final class MenuBarItemManager {
  private enum SpacerPlacementMethod: CustomStringConvertible {
    case menuBarAgentPosition
    case measurement

    var description: String {
      switch self {
      case .menuBarAgentPosition: "MenuBarAgent position"
      case .measurement: "measurement"
      }
    }
  }

  private static let menuBarPreferencesPath = URL.homeDirectory.appending(
    path: "Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist"
  ).path(percentEncoded: false)

  private static let placementAttemptLimit = 8
  private static let positionIncrement = 0.1
  private static let layoutSettlingAttemptLimit = 20
  private static let layoutSettlingInterval: Duration = .milliseconds(50)

  private let startDate = Date.now
  private let boundaryStatusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var spacerStatusItems: [NSStatusItem] = []
  private var hideItemsTask: Task<Void, Never>?
  private var spacerPlacementMethod: SpacerPlacementMethod?
  private var screenParametersObservationTask: Task<Void, Never>?
  private var isHidingItems = false

  private var hidingStatusItemLength: CGFloat? {
    // MenuBarAgent ignores a status item with a window wider than half of the display width.
    let length = ((NSScreen.screens.map(\.frame.width).min() ?? 0) / 2).rounded(.down)

    return length > 0 ? length : nil
  }

  init() {
    boundaryStatusItem.behavior = .terminationOnRemoval
    boundaryStatusItem.button?.isEnabled = false

    self.screenParametersObservationTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: NSApplication.didChangeScreenParametersNotification
      ) {
        guard let self else {
          break
        }

        guard isHidingItems else {
          continue
        }

        hideItems()
      }
    }
  }

  isolated deinit {
    hideItemsTask?.cancel()
    screenParametersObservationTask?.cancel()
    removeSpacerStatusItems()
    NSStatusBar.system.removeStatusItem(boundaryStatusItem)
  }

  func showItems() {
    hideItemsTask?.cancel()

    self.hideItemsTask = nil
    self.isHidingItems = false

    removeSpacerStatusItems()

    boundaryStatusItem.length = NSStatusItem.variableLength
    boundaryStatusItem.button?.title = "􂉏"
  }

  func hideItems() {
    hideItemsTask?.cancel()

    self.hideItemsTask = nil
    self.isHidingItems = true

    guard let hidingStatusItemLength else {
      return
    }

    boundaryStatusItem.button?.title = ""

    let spacerStatusItemCount = spacerStatusItemCount(forLength: hidingStatusItemLength)

    guard spacerStatusItems.count != spacerStatusItemCount else {
      widenStatusItems(to: hidingStatusItemLength)
      return
    }

    removeSpacerStatusItems()

    // MenuBarAgent's preferences are only readable with Full Disk Access.
    if let boundaryStatusItemPosition = menuBarAgentPosition(of: boundaryStatusItem) {
      self.spacerPlacementMethod = .menuBarAgentPosition

      addSpacerStatusItems(count: spacerStatusItemCount, besideBoundaryAt: boundaryStatusItemPosition)
      widenStatusItems(to: hidingStatusItemLength)

      return
    }

    self.spacerPlacementMethod = .measurement

    // Spacer status items are placed by measuring the boundary item on screen.
    setLength(of: boundaryStatusItem, to: 1)

    self.hideItemsTask = Task { [weak self] in
      await self?.addMeasuredSpacerStatusItems(count: spacerStatusItemCount)

      guard let self, !Task.isCancelled else {
        return
      }

      widenStatusItems(to: hidingStatusItemLength)

      self.hideItemsTask = nil
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
        Boundary status item MenuBarAgent position: \(menuBarAgentPosition(of: boundaryStatusItem).map { "\($0)" } ?? "<unavailable>")
        Spacer status item placement: \(spacerPlacementMethod?.description ?? "<none placed>")
        Spacer status items: \(spacerStatusItems.map { "\($0.autosaveName ?? "<none>") (\($0.button?.window?.frame.width ?? 0))" }.joined(separator: ", "))
      """
    )
  }

  private func spacerStatusItemCount(forLength length: CGFloat) -> Int {
    // Enough spacers that, with the boundary item, they're at least as wide as the widest display.
    return max(Int(((NSScreen.screens.map(\.frame.width).max() ?? 0) / length).rounded(.up)) - 1, 1)
  }

  private func makeSpacerStatusItem(index: Int, preferredPosition: Double) -> NSStatusItem {
    // MenuBarAgent remembers a position per autosave name and ignores the preferred position for a name it has already
    // placed, so the name has to encode the position it is placed at.
    let autosaveName = "Spacer-\(preferredPosition.formatted(.fixedPoint(fractionLength: 1)))-\(index)"

    // Written before `autosaveName` is set below so that its preferred position is applied.
    UserDefaults.standard.set(preferredPosition, forKey: NSStatusItem.preferredPositionKey(for: autosaveName))

    let spacerStatusItem = NSStatusBar.system.statusItem(withLength: 1)
    spacerStatusItem.autosaveName = autosaveName
    spacerStatusItem.behavior = .terminationOnRemoval
    spacerStatusItem.button?.isEnabled = false

    return spacerStatusItem
  }

  private func menuBarAgentPosition(of statusItem: NSStatusItem) -> Double? {
    guard
      let autosaveName = statusItem.autosaveName,
      // Requires Full Disk Access permission.
      let data = FileManager.default.contents(atPath: Self.menuBarPreferencesPath),
      let preferences = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
      let positions = preferences["TrailingItemPreferredPositions"] as? [String: Double]
    else {
      return nil
    }

    return positions["status:\(ProcessInfo.processInfo.processName)::\(autosaveName)"]
  }

  private func addSpacerStatusItems(count: Int, besideBoundaryAt boundaryStatusItemPosition: Double) {
    for index in 0..<count {
      let spacerStatusItem = makeSpacerStatusItem(
        index: index,
        preferredPosition: boundaryStatusItemPosition + Double(index + 1) * Self.positionIncrement
      )

      self.spacerStatusItems.append(spacerStatusItem)
    }
  }

  private func addMeasuredSpacerStatusItems(count: Int) async {
    guard
      let boundaryStatusItemFrame = await settledFrame(of: boundaryStatusItem),
      let screen = boundaryStatusItem.button?.window?.screen ?? NSScreen.main
    else {
      if !Task.isCancelled {
        Log.error("Failed to add measured spacer status items (unable to measure the boundary status item).")
      }

      return
    }

    var anchorStatusItem = boundaryStatusItem
    var position = screen.frame.maxX - boundaryStatusItemFrame.maxX

    for index in 0..<count {
      guard
        let placement = await addMeasuredSpacerStatusItem(leftOf: anchorStatusItem, startingAt: position, index: index)
      else {
        if !Task.isCancelled {
          Log.error("Failed to place spacer status item \(spacerStatusItems.count + 1) of \(count).")
        }

        return
      }

      self.spacerStatusItems.append(placement.statusItem)

      anchorStatusItem = placement.statusItem
      position = placement.position + Self.positionIncrement
    }
  }

  private func addMeasuredSpacerStatusItem(
    leftOf anchorStatusItem: NSStatusItem,
    startingAt startingPosition: Double,
    index: Int
  ) async -> (statusItem: NSStatusItem, position: Double)? {
    var position = startingPosition

    for attempt in 0..<Self.placementAttemptLimit {
      guard !Task.isCancelled else {
        return nil
      }

      let spacerStatusItem = makeSpacerStatusItem(index: index, preferredPosition: position)
      let spacerStatusItemFrame = await settledFrame(of: spacerStatusItem)
      let anchorStatusItemFrame = anchorStatusItem.button?.window?.frame

      guard !Task.isCancelled else {
        removeSpacerStatusItem(spacerStatusItem)
        return nil
      }

      if let spacerStatusItemFrame, let anchorStatusItemFrame, !anchorStatusItemFrame.isEmpty {
        let gap = anchorStatusItemFrame.minX - spacerStatusItemFrame.maxX

        guard abs(gap) >= 1 else {
          return (spacerStatusItem, position)
        }

        position -= gap
      } else {
        position += Double(attempt + 1)
      }

      removeSpacerStatusItem(spacerStatusItem)
    }

    return nil
  }

  private func settledFrame(of statusItem: NSStatusItem) async -> CGRect? {
    var previousFrame: CGRect?

    for _ in 0..<Self.layoutSettlingAttemptLimit {
      let frame = statusItem.button?.window?.frame

      if let frame, !frame.isEmpty, frame == previousFrame {
        return frame
      }

      previousFrame = frame

      do {
        try await Task.sleep(for: Self.layoutSettlingInterval)
      } catch {
        return nil
      }
    }

    return nil
  }

  private func widenStatusItems(to length: CGFloat) {
    for statusItem in [boundaryStatusItem] + spacerStatusItems {
      setLength(of: statusItem, to: length)
    }
  }

  private func setLength(of statusItem: NSStatusItem, to length: CGFloat) {
    statusItem.length = length

    if let windowWidth = statusItem.button?.window?.frame.width, windowWidth > length {
      statusItem.length -= windowWidth - length
    }
  }

  private func removeSpacerStatusItem(_ statusItem: NSStatusItem) {
    NSStatusBar.system.removeStatusItem(statusItem)

    if let autosaveName = statusItem.autosaveName {
      UserDefaults.standard.removeObject(forKey: NSStatusItem.preferredPositionKey(for: autosaveName))
    }
  }

  private func removeSpacerStatusItems() {
    for spacerStatusItem in spacerStatusItems {
      removeSpacerStatusItem(spacerStatusItem)
    }

    self.spacerStatusItems.removeAll()
    self.spacerPlacementMethod = nil
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
