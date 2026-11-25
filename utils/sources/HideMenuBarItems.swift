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

  private enum FrameSettlingResult {
    case settled(CGRect)
    case notLaidOut
    case unsettled
  }

  private enum ProbeResult {
    case rightOfBoundary(distance: CGFloat)
    case adjacent
    case leftOfNextItem(distance: CGFloat)
    case overflowedLeft
  }

  private static let menuBarPreferencesPath = URL.homeDirectory.appending(
    path: "Library/Group Containers/com.apple.MenuBar/Library/Preferences/com.apple.MenuBar.plist"
  ).path(percentEncoded: false)

  private static let placementAttemptLimit = 12
  private static let initialSearchStep = 24.0
  private static let positionIncrement = 0.1
  private static let positionResolution = 1.0
  private static let adjacencyTolerance: CGFloat = 1
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
    // MenuBarAgent ignores a status item whose window is wider than half the display width.
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

    // Fall back to measuring on screen; shrink the boundary item so it stays visible while probing.
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
    // Enough spacers to span the widest display alongside the boundary item.
    return max(Int(((NSScreen.screens.map(\.frame.width).max() ?? 0) / length).rounded(.up)) - 1, 1)
  }

  private func makeSpacerStatusItem(autosaveName: String, preferredPosition: Double) -> NSStatusItem {
    // Written before `autosaveName` is set so MenuBarAgent applies it; callers encode the position in the name because
    // MenuBarAgent ignores preferred positions for names it has already seen.
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
      let preferredPosition = Self.roundedPosition(
        boundaryStatusItemPosition + Double(index + 1) * Self.positionIncrement
      )
      let autosaveName = "Spacer-\(preferredPosition.formatted(.fixedPoint(fractionLength: 1)))-\(index)"
      let spacerStatusItem = makeSpacerStatusItem(autosaveName: autosaveName, preferredPosition: preferredPosition)

      self.spacerStatusItems.append(spacerStatusItem)
    }
  }

  private func addMeasuredSpacerStatusItems(count: Int) async {
    guard
      case .settled(let boundaryStatusItemFrame) = await settledFrame(of: boundaryStatusItem),
      let screen = boundaryStatusItem.button?.window?.screen ?? NSScreen.main
    else {
      if !Task.isCancelled {
        Log.error("Failed to add measured spacer status items (unable to measure the boundary status item).")
      }

      return
    }

    guard
      let boundaryStatusItemPosition = await measureBoundaryStatusItemPosition(
        startingAt: screen.frame.maxX - boundaryStatusItemFrame.maxX
      )
    else {
      if !Task.isCancelled {
        Log.error("Failed to add measured spacer status items (unable to find the boundary status item's position).")
      }

      return
    }

    addSpacerStatusItems(count: count, besideBoundaryAt: boundaryStatusItemPosition)
  }

  private func measureBoundaryStatusItemPosition(startingAt startingPosition: Double) async -> Double? {
    // MenuBarAgent orders items by stored positions (larger = further left) that only roughly track screen distance.
    // Bracket the boundary item's position with probes on either side, then bisect to the lowest adjacent position so
    // absent items cannot return between the boundary item and spacers; callers place spacers just above to avoid ties.
    var lowerBound: Double?
    var upperBound: Double?
    var lowestAdjacentPosition: Double?
    var position = max(Self.roundedPosition(startingPosition), 0)
    var step = Self.initialSearchStep

    for _ in 0..<Self.placementAttemptLimit {
      guard let probeResult = await probeSpacerStatusItem(at: position) else {
        guard !Task.isCancelled else {
          return nil
        }

        // Frame didn't settle; retry the same position.
        continue
      }

      let jumpDistance: Double

      switch probeResult {
      case .rightOfBoundary(let distance):
        lowerBound = position
        jumpDistance = distance

      case .adjacent:
        upperBound = position
        lowestAdjacentPosition = position
        jumpDistance = 0

      case .leftOfNextItem(let distance):
        upperBound = position
        jumpDistance = distance

      case .overflowedLeft:
        upperBound = position
        jumpDistance = 0
      }

      if let lowerBound, let upperBound {
        if let lowestAdjacentPosition, upperBound - lowerBound <= Self.positionResolution {
          return lowestAdjacentPosition
        }

        // Autosave names quantize positions to `positionIncrement`, so stop when no distinct midpoint exists.
        let midpoint = Self.roundedPosition((lowerBound + upperBound) / 2)

        guard midpoint > lowerBound, midpoint < upperBound else {
          return lowestAdjacentPosition
        }

        position = midpoint

      } else if let lowerBound {
        position = Self.roundedPosition(lowerBound + max(step, jumpDistance))
        step *= 2

      } else if let upperBound {
        guard upperBound > 0 else {
          return lowestAdjacentPosition
        }

        position = max(Self.roundedPosition(upperBound - max(step, jumpDistance)), 0)
        step *= 2
      }
    }

    return lowestAdjacentPosition
  }

  private func probeSpacerStatusItem(at position: Double) async -> ProbeResult? {
    let autosaveName = "Probe-\(position.formatted(.fixedPoint(fractionLength: 1)))"
    let spacerStatusItem = makeSpacerStatusItem(autosaveName: autosaveName, preferredPosition: position)
    let settlingResult = await settledFrame(of: spacerStatusItem)
    let boundaryStatusItemFrame = boundaryStatusItem.button?.window?.frame

    removeSpacerStatusItem(spacerStatusItem)

    guard
      !Task.isCancelled,
      let boundaryStatusItemFrame,
      !boundaryStatusItemFrame.isEmpty
    else {
      return nil
    }

    switch settlingResult {
    case .settled(let spacerStatusItemFrame):
      // Positive if left of the boundary with a gap; negative if overlapping or to its right.
      let gap = boundaryStatusItemFrame.minX - spacerStatusItemFrame.maxX

      if gap <= -Self.adjacencyTolerance {
        return .rightOfBoundary(distance: abs(gap))
      }

      if gap < Self.adjacencyTolerance {
        return .adjacent
      }

      return .leftOfNextItem(distance: gap)

    case .notLaidOut:
      // MenuBarAgent drops items from left to right when out of space, so an unplaced probe is too far left.
      return .overflowedLeft

    case .unsettled:
      return nil
    }
  }

  private func settledFrame(of statusItem: NSStatusItem) async -> FrameSettlingResult {
    var previousFrame: CGRect?
    var hasSeenNonEmptyFrame = false

    for _ in 0..<Self.layoutSettlingAttemptLimit {
      let frame = statusItem.button?.window?.frame

      if let frame, !frame.isEmpty {
        if frame == previousFrame {
          return .settled(frame)
        }

        hasSeenNonEmptyFrame = true
      }

      previousFrame = frame

      do {
        try await Task.sleep(for: Self.layoutSettlingInterval)
      } catch {
        return .unsettled
      }
    }

    return hasSeenNonEmptyFrame ? .unsettled : .notLaidOut
  }

  private static func roundedPosition(_ position: Double) -> Double {
    let scale = (1 / positionIncrement).rounded()
    return (position * scale).rounded() / scale
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
