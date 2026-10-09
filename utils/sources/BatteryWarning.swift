// Shared: Agent Log NSStatusItem

import AppKit
import IOKit.ps
import notify

enum Configuration {
  static let subsystem = "industries.britown.BatteryWarning"
  static let warningThresholdChargePercentage = 10
  static let urgentWarningThresholdMinutesRemaining = 15
  static let urgentWarningSoundFilePath = "~/.dotfiles/utils/assets/low-battery-warning.wav"
}

struct BatteryStatus: Equatable {
  enum Error: Swift.Error, LocalizedError {
    case failedToRegisterForNotifications(status: UInt32)

    var errorDescription: String? {
      switch self {
      case .failedToRegisterForNotifications(let status):
        "Failed to register for power source notifications (status: \(status))."
      }
    }
  }

  enum Severity {
    case warning
    case urgent
  }

  let isOnBatteryPower: Bool
  let chargePercentage: Int
  let minutesRemaining: Int?

  var severity: Severity? {
    guard isOnBatteryPower else {
      return nil
    }

    if let minutesRemaining, minutesRemaining <= Configuration.urgentWarningThresholdMinutesRemaining {
      return .urgent
    }

    return chargePercentage <= Configuration.warningThresholdChargePercentage ? .warning : nil
  }

  init?(powerSourceDescription description: [String: Any]) {
    guard
      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
      let currentCapacity = description[kIOPSCurrentCapacityKey] as? Int,
      let maxCapacity = description[kIOPSMaxCapacityKey] as? Int,
      maxCapacity > 0
    else {
      return nil
    }

    let isOnBatteryPower = description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue
    let timeToEmpty = description[kIOPSTimeToEmptyKey] as? Int

    self.isOnBatteryPower = isOnBatteryPower
    self.chargePercentage = currentCapacity * 100 / maxCapacity
    self.minutesRemaining = isOnBatteryPower ? timeToEmpty.flatMap { $0 >= 0 ? $0 : nil } : nil
  }

  static func current() -> BatteryStatus? {
    guard
      let powerSourcesInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
      let powerSources = IOPSCopyPowerSourcesList(powerSourcesInfo)?.takeRetainedValue() as? [CFTypeRef]
    else {
      return nil
    }

    return powerSources
      .lazy
      .compactMap { IOPSGetPowerSourceDescription(powerSourcesInfo, $0)?.takeUnretainedValue() as? [String: Any] }
      .compactMap(BatteryStatus.init(powerSourceDescription:))
      .first
  }

  static func updates() throws -> AsyncStream<BatteryStatus?> {
    let (stream, continuation) = AsyncStream.makeStream(of: BatteryStatus?.self, bufferingPolicy: .bufferingNewest(1))

    var notifyToken = NOTIFY_TOKEN_INVALID

    let status = notify_register_dispatch(kIOPSNotifyAnyPowerSource, &notifyToken, .main) { _ in
      continuation.yield(current())
    }

    guard status == NOTIFY_STATUS_OK else {
      throw Error.failedToRegisterForNotifications(status: status)
    }

    continuation.onTermination = { [notifyToken] _ in
      notify_cancel(notifyToken)
    }

    continuation.yield(current())

    return stream
  }
}

@MainActor
final class StatusItemManager {
  private static let autosaveName = "BatteryWarning"
  private static let pulseAnimationKey = "pulse"
  private static let pulseAnimation: CABasicAnimation = {
    let animation = CABasicAnimation(keyPath: #keyPath(CALayer.opacity))
    animation.fromValue = 1
    animation.toValue = 0.5
    animation.duration = 0.75
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

    return animation
  }()
  private static let urgentWarningSound = NSSound(
    contentsOf: URL(filePath: Configuration.urgentWarningSoundFilePath),
    byReference: true
  )

  private let startDate = Date.now
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
  private var isAlwaysVisible = false
  private var batteryStatus: BatteryStatus?
  private var monitoringTask: Task<Void, Never>?

  init(batteryStatusUpdates: AsyncStream<BatteryStatus?>) {
    statusItem.autosaveName = Self.autosaveName
    statusItem.behavior = .terminationOnRemoval
    statusItem.isVisiblePreservingPosition = false
    statusItem.button?.font = .preferredFont(forTextStyle: .subheadline)
    statusItem.button?.wantsLayer = true

    self.monitoringTask = Task { [weak self] in
      for await batteryStatus in batteryStatusUpdates {
        guard let self else {
          break
        }

        let previousSeverity = self.batteryStatus?.severity

        self.batteryStatus = batteryStatus

        if batteryStatus?.severity == .urgent, previousSeverity != .urgent {
          Self.urgentWarningSound?.play()
        }

        updateStatusItem()
      }
    }
  }

  deinit {
    monitoringTask?.cancel()
  }

  func toggleAlwaysVisible() {
    self.isAlwaysVisible.toggle()
    updateStatusItem()
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Status item visible: \(statusItem.isVisible)
        Status item always visible: \(isAlwaysVisible)
        Status item title: \(statusItem.button?.title ?? "<none>")
        On battery power: \(batteryStatus.map { "\($0.isOnBatteryPower)" } ?? "<no battery>")
        Charge: \(batteryStatus.map { $0.chargePercentage.formatted(.percent) } ?? "<no battery>")
        Minutes remaining: \(batteryStatus?.minutesRemaining.map(String.init) ?? "<unknown>")
        Severity: \(batteryStatus?.severity.map { "\($0)" } ?? "<none>")
      """
    )
  }

  private func updateStatusItem() {
    let severity = batteryStatus?.severity

    statusItem.isVisiblePreservingPosition = batteryStatus != nil && (isAlwaysVisible || severity != nil)

    guard statusItem.isVisible, let batteryStatus, let button = statusItem.button else {
      return
    }

    let title = title(for: batteryStatus)

    switch severity {
    case .warning, nil:
      button.title = title

    case .urgent:
      button.attributedTitle = NSAttributedString(
        string: title,
        attributes: [.font: button.font as Any, .foregroundColor: NSColor.systemRed]
      )
    }

    setPulsing(severity == .urgent)
  }

  private func title(for batteryStatus: BatteryStatus) -> String {
    guard let minutesRemaining = batteryStatus.minutesRemaining else {
      return batteryStatus.chargePercentage.formatted(.percent)
    }

    return Duration.seconds(minutesRemaining * 60).formatted(.time(pattern: .hourMinute))
  }

  private func setPulsing(_ isPulsing: Bool) {
    guard let layer = statusItem.button?.layer else {
      return
    }

    guard isPulsing else {
      layer.removeAnimation(forKey: Self.pulseAnimationKey)
      return
    }

    if layer.animation(forKey: Self.pulseAnimationKey) == nil {
      layer.add(Self.pulseAnimation, forKey: Self.pulseAnimationKey)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var statusItemManager: StatusItemManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.statusItemManager = StatusItemManager(batteryStatusUpdates: try BatteryStatus.updates())
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.statusItemManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .toggle: statusItemManager?.toggleAlwaysVisible()
    case .printLog: statusItemManager?.logDiagnosticReport()
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
enum BatteryWarning {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .accessory) {
      AppDelegate()
    }
  }
}
