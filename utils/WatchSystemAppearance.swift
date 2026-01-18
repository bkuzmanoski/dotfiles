import Foundation

let processGroupPID = getpgrp()
let processGroupSource = DispatchSource.makeProcessSource(identifier: processGroupPID, eventMask: .exit, queue: .main)
processGroupSource.setEventHandler { exit(0) }
processGroupSource.resume()

let signals = [SIGHUP, SIGINT, SIGTERM]
let signalSources = signals.map { signal in
  let source = DispatchSource.makeSignalSource(signal: signal, queue: .main)
  source.setEventHandler { exit(0) }
  source.resume()

  return source
}

func printSystemAppearance() {
  UserDefaults.standard.synchronize()

  let appearance = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
  let mode = (appearance == "Dark") ? "Dark" : "Light"

  print(mode)
  fflush(stdout)
}

printSystemAppearance()

let notification = NSNotification.Name("AppleInterfaceThemeChangedNotification")
DistributedNotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { _ in
  printSystemAppearance()
}

RunLoop.main.run()
