import AppKit

enum Constants {
  static let subsystem = "industries.britown.MenuBarItemHider"
  static let lockFileName = "\(subsystem).lock"
  static let notificationName = Notification.Name("\(subsystem).command")
  static let notificationUserInfoKey = "arguments"
  static let menuBarItemTitle = "􂉏"
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
    guard let signalName = strsignal(signal) else {
      return "Unknown signal (\(signal))"
    }

    return String(cString: signalName)
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

      continuation.onTermination = { _ in
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
    case failedToAcquireLock(errno: Int32)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: "Instance already running."
      case .failedToAcquireLock(let errno): "Failed to acquire lock: \(String(cString: strerror(errno)))"
      }
    }
  }

  private let lockFilePath = NSTemporaryDirectory().appending(Constants.lockFileName)
  private var lockFileDescriptor: CInt

  init() throws {
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)

    guard fd != -1 else {
      throw Error.failedToAcquireLock(errno: errno)
    }

    guard flock(fd, LOCK_EX | LOCK_NB) != -1 else {
      close(fd)

      guard errno == EWOULDBLOCK else {
        throw Error.failedToAcquireLock(errno: errno)
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

@MainActor
class StatusItemController {
  let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

  init() {
    statusItem.button?.isEnabled = false
  }

  deinit {
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  func showItem() {
    statusItem.length = NSStatusItem.variableLength
    statusItem.button?.title = Constants.menuBarItemTitle
  }

  func hideItem() {
    statusItem.length = 6016
    statusItem.button?.title = ""
  }

  func toggle() {
    statusItem.length == NSStatusItem.variableLength ? hideItem() : showItem()
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private let singletonLock: SingletonLock
  private var statusItemController: StatusItemController?

  init(singletonLock: SingletonLock) {
    self.singletonLock = singletonLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    observeSignals()
    observeCommands()

    self.statusItemController = StatusItemController()

    statusItemController?.hideItem()
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
    case "toggle": await statusItemController?.toggle()
    case "quit": await NSApplication.shared.terminate(nil)
    default: return
    }
  }
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
    print("Already running, specify \"toggle\" or \"quit\" as an argument.")
    exit(0)
  }

  Command(arguments: arguments).send()
  exit(0)

} catch {
  FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
  exit(1)
}
