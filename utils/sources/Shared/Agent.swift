// Shared: Log ProcessSignals SingleInstanceLock

import AppKit
import System

protocol AgentIPCCommand: RawRepresentable<String>, CaseIterable, Sendable {
  static var printLog: Self { get }
}

@MainActor
protocol AgentDelegate: NSApplicationDelegate, Sendable {
  associatedtype IPCCommand: AgentIPCCommand

  func handleIPCCommand(_ ipcCommand: IPCCommand)
}

@MainActor
enum Agent {
  private static let notificationUserInfoKey = "command"

  static func run<Delegate: AgentDelegate>(
    subsystem: String,
    activationPolicy: NSApplication.ActivationPolicy,
    makeDelegate: () -> Delegate
  ) -> Never {
    let singleInstanceLock: SingleInstanceLock

    do {
      singleInstanceLock = try SingleInstanceLock(path: temporaryFilePath(subsystem: subsystem, pathExtension: "lock"))

    } catch SingleInstanceLock.Error.instanceAlreadyRunning {
      sendIPCCommand(Delegate.IPCCommand.self, subsystem: subsystem)

    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }

    if isatty(FileDescriptor.standardOutput.rawValue) == 0 {
      do {
        try Log.redirectOutput(to: temporaryFilePath(subsystem: subsystem, pathExtension: "log"))
      } catch {
        Log.error("Failed to redirect output: \(error.localizedDescription)")
      }
    }

    let delegate = makeDelegate()
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(activationPolicy)

    NotificationCenter.default.addObserver(
      forName: NSApplication.didFinishLaunchingNotification,
      object: application,
      queue: nil
    ) { _ in
      Task { @MainActor in
        await observeProcessSignals()
      }

      Task { @MainActor in
        await observeIPCCommands(for: delegate, subsystem: subsystem)
      }
    }

    withExtendedLifetime((singleInstanceLock, delegate)) {
      application.run()
    }

    exit(EXIT_SUCCESS)
  }

  private static func observeProcessSignals() async {
    for await _ in ProcessSignals.stream(for: SIGINT, SIGTERM, SIGHUP) {
      NSApplication.shared.terminate(nil)
    }
  }

  private static func observeIPCCommands<Delegate: AgentDelegate>(for delegate: Delegate, subsystem: String) async {
    for await notification in DistributedNotificationCenter.default().notifications(
      named: notificationName(subsystem: subsystem)
    ) {
      guard
        let userInfo = notification.userInfo,
        let ipcCommandRawValue = userInfo[notificationUserInfoKey] as? String,
        let ipcCommand = Delegate.IPCCommand(rawValue: ipcCommandRawValue.lowercased())
      else {
        continue
      }

      delegate.handleIPCCommand(ipcCommand)
    }
  }

  private static func sendIPCCommand<IPCCommand: AgentIPCCommand>(
    _ ipcCommandType: IPCCommand.Type,
    subsystem: String
  ) -> Never {
    let arguments = CommandLine.arguments.dropFirst()

    lazy var usageDescription =
      "Usage: \(ProcessInfo.processInfo.processName) [\(IPCCommand.allCases.map(\.rawValue).joined(separator: "|"))]"

    guard let argument = arguments.first else {
      Log.error("Already running.\n\n\(usageDescription)")
      exit(EX_USAGE)
    }

    guard arguments.dropFirst().isEmpty else {
      Log.error("Too many arguments.\n\n\(usageDescription)")
      exit(EX_USAGE)
    }

    guard let ipcCommand = IPCCommand(rawValue: argument.lowercased()) else {
      Log.error("Unknown command.\n\n\(usageDescription)")
      exit(EX_USAGE)
    }

    DistributedNotificationCenter.default().postNotificationName(
      notificationName(subsystem: subsystem),
      object: nil,
      userInfo: [notificationUserInfoKey: ipcCommand.rawValue],
      deliverImmediately: true
    )

    if ipcCommand == .printLog {
      Thread.sleep(forTimeInterval: 0.2)

      let logFilePath = temporaryFilePath(subsystem: subsystem, pathExtension: "log")

      guard FileManager.default.fileExists(atPath: logFilePath.string) else {
        Log.error("Log file does not exist.")
        exit(EX_NOINPUT)
      }

      print("Log file path: \(logFilePath)\n")

      do {
        let logContents = try String(contentsOfFile: logFilePath.string, encoding: .utf8)

        if logContents.isEmpty {
          print("<EMPTY>")
        } else {
          print(logContents)
        }
      } catch {
        Log.error("Failed to read log file: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
      }
    }

    exit(EXIT_SUCCESS)
  }

  private static func notificationName(subsystem: String) -> Notification.Name {
    return Notification.Name("\(subsystem).IPCCommand")
  }

  private static func temporaryFilePath(subsystem: String, pathExtension: String) -> FilePath {
    return FilePath(URL.temporaryDirectory.appending(path: "\(subsystem).\(pathExtension)").path(percentEncoded: false))
  }
}
