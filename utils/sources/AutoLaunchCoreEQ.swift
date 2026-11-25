// Shared: Agent AudioDevice Log

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.AutoLaunchCoreEQ"
  static let targetDeviceNameSubstring = "AirPods Pro"
  static let applicationBundleIdentifier = "com.andreypudov.coreeq"
  static let launchDelay: Duration = .seconds(3)
  static let quitDelay: Duration = .seconds(10)
}

@MainActor
final class ApplicationManager {
  private enum Action {
    case launch
    case quit
  }

  private struct PendingAction {
    let action: Action
    let task: Task<Void, Never>
  }

  private let startDate = Date.now
  private var defaultOutputDevice: AudioDevice?
  private var defaultOutputDeviceName: String?
  private var isTargetDeviceDefaultOutput = false
  private var pendingAction: PendingAction?
  private var monitoringTask: Task<Void, Never>?

  private var isApplicationRunning: Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: Configuration.applicationBundleIdentifier).isEmpty
  }

  init(defaultOutputDeviceUpdates: AsyncStream<AudioDevice?>) {
    self.monitoringTask = Task { [weak self] in
      for await defaultOutputDevice in defaultOutputDeviceUpdates {
        guard let self else {
          break
        }

        handleDefaultOutputDeviceChange(defaultOutputDevice)
      }
    }
  }

  deinit {
    monitoringTask?.cancel()
    pendingAction?.task.cancel()
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Default output device: \(defaultOutputDevice.map { "\(defaultOutputDeviceName ?? "<unknown>") (\($0.id))" } ?? "<none>")
        Target device is default output: \(isTargetDeviceDefaultOutput)
        Application running: \(isApplicationRunning)
        Pending action: \(pendingAction.map { "\($0.action)" } ?? "<none>")
      """
    )
  }

  private func handleDefaultOutputDeviceChange(_ defaultOutputDevice: AudioDevice?) {
    self.defaultOutputDevice = defaultOutputDevice

    let defaultOutputDeviceName: String?

    do {
      defaultOutputDeviceName = try defaultOutputDevice?.name
    } catch {
      Log.error(error.localizedDescription)

      self.defaultOutputDeviceName = nil

      return
    }

    self.defaultOutputDeviceName = defaultOutputDeviceName

    let isTargetDeviceDefaultOutput =
      defaultOutputDeviceName?.localizedCaseInsensitiveContains(Configuration.targetDeviceNameSubstring) == true

    guard isTargetDeviceDefaultOutput != self.isTargetDeviceDefaultOutput else {
      return
    }

    self.isTargetDeviceDefaultOutput = isTargetDeviceDefaultOutput

    cancelPendingAction()

    if isTargetDeviceDefaultOutput {
      scheduleAction(.launch, after: Configuration.launchDelay)
    } else {
      scheduleAction(.quit, after: Configuration.quitDelay)
    }
  }

  private func scheduleAction(_ action: Action, after delay: Duration) {
    self.pendingAction = PendingAction(
      action: action,
      task: Task { [weak self] in
        do {
          try await Task.sleep(for: delay)
        } catch {
          return
        }

        guard let self, !Task.isCancelled else {
          return
        }

        self.pendingAction = nil

        await perform(action)
      }
    )
  }

  private func cancelPendingAction() {
    guard let pendingAction else {
      return
    }

    pendingAction.task.cancel()

    self.pendingAction = nil
  }

  private func perform(_ action: Action) async {
    switch action {
    case .launch: await launchApplication()
    case .quit: quitApplication()
    }
  }

  private func launchApplication() async {
    guard !isApplicationRunning else {
      return
    }

    guard
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: Configuration.applicationBundleIdentifier
      )
    else {
      Log.error("Application with bundle identifier \(Configuration.applicationBundleIdentifier) not found.")
      return
    }

    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false

    do {
      try await NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    } catch {
      Log.error("Failed to launch application: \(error.localizedDescription)")
    }
  }

  private func quitApplication() {
    for application in NSRunningApplication.runningApplications(
      withBundleIdentifier: Configuration.applicationBundleIdentifier
    ) where !application.terminate() {
      Log.error("Failed to quit application.")
    }
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var applicationManager: ApplicationManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.applicationManager = ApplicationManager(
        defaultOutputDeviceUpdates: try AudioDevice.defaultDeviceUpdates(for: .output)
      )
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.applicationManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .printLog: applicationManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case printLog = "print-log"
  case quit
}

@main
enum AutoLaunchCoreEQ {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
