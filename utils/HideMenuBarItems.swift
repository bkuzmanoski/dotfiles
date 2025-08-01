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
      case .interrupted(let signal): return "Interrupted with signal \(Signal.name(for: signal))"
      }
    }
  }

  static func name(for signal: CInt) -> String {
    guard let namePtr = strsignal(signal) else { return "Unknown signal (\(signal))" }
    return String(cString: namePtr)
  }

  static func stream(for signals: [CInt]) -> AsyncStream<CInt> {
    AsyncStream { continuation in
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

actor SingletonLock {
  enum Error: Swift.Error, LocalizedError {
    case instanceAlreadyRunning
    case lockFileError(String)

    var errorDescription: String? {
      switch self {
      case .instanceAlreadyRunning: return "Instance already running."
      case .lockFileError(let message): return "Failed to acquire lock: \(message)"
      }
    }
  }

  private let lockFilePath = NSTemporaryDirectory().appending(Constants.lockFileName)
  private var lockFileDescriptor: CInt

  init() throws {
    let fd = open(lockFilePath, O_CREAT | O_RDWR, 0o644)
    if fd == -1 {
      throw Error.lockFileError(String(cString: strerror(errno)))
    }

    if flock(fd, LOCK_EX | LOCK_NB) == -1 {
      close(fd)
      guard errno == EWOULDBLOCK else {
        throw Error.lockFileError("Failed to acquire lock: \(String(cString: strerror(errno)))")
      }
      throw Error.instanceAlreadyRunning
    }

    lockFileDescriptor = fd
  }

  deinit {
    flock(lockFileDescriptor, LOCK_UN)
    close(lockFileDescriptor)
    try? FileManager.default.removeItem(atPath: lockFilePath)
  }
}

@MainActor
class MenuBarItemController {
  let statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

  init() {
    statusItem.button?.isEnabled = false
  }

  deinit {
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  func show() {
    statusItem.length = NSStatusItem.variableLength
    statusItem.button?.title = Constants.menuBarItemTitle
  }

  func hide() {
    statusItem.length = 6016
    statusItem.button?.title = ""
  }

  func toggle() {
    statusItem.length == NSStatusItem.variableLength ? hide() : show()
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private var singletonLock: SingletonLock
  private var menuBarController: MenuBarItemController!

  init(singletonLock: SingletonLock) {
    self.singletonLock = singletonLock
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    menuBarController = MenuBarItemController()
    menuBarController.hide()

    Task {
      let stream = DistributedNotificationCenter.default().notifications(named: Constants.notificationName)
      for await notification in stream {
        guard
          let userInfo = notification.userInfo,
          let arguments = userInfo[Constants.notificationUserInfoKey] as? [String]
        else {
          continue
        }

        await handleCommand(with: arguments)
      }
    }

    Task {
      for await signal in Signal.stream(for: [SIGHUP, SIGINT, SIGTERM]) {
        print("Received \(Signal.name(for: signal)), shutting down.")
        NSApp.terminate(nil)
      }
    }
  }

  private func handleCommand(with arguments: [String]) async {
    guard let command = arguments.first else { return }
    switch command {
    case "toggle": await menuBarController.toggle()
    case "quit": await NSApp.terminate(nil)
    default: return
    }
  }
}

do {
  let singletonLock = try SingletonLock()
  let delegate = AppDelegate(singletonLock: singletonLock)
  let app = NSApplication.shared
  app.delegate = delegate
  app.run()
} catch SingletonLock.Error.instanceAlreadyRunning {
  let arguments = Array(CommandLine.arguments.dropFirst())
  guard !arguments.isEmpty else {
    print("Already running, specify \"toggle\" or \"quit\" as an argument.")
    exit(0)
  }
  Command(arguments: arguments).send()
  exit(0)
} catch {
  print("An error occurred on startup: \(error.localizedDescription)")
  exit(1)
}
