// Shared: Accessibility Log

import AppKit

@MainActor
final class EventTap {
  enum Error: Swift.Error, LocalizedError {
    case failedToCreateEventTap
    case failedToCreateRunLoopSource

    var errorDescription: String? {
      switch self {
      case .failedToCreateEventTap: "Failed to create event tap."
      case .failedToCreateRunLoopSource: "Failed to create run loop source for event tap."
      }
    }
  }

  var eventHandler: ((CGEvent) -> Bool)?
  var eventObserver: ((CGEvent) -> Void)?
  var interruptionHandler: (() -> Void)?

  var isEnabled = false {
    didSet {
      if let machPort, CGEvent.tapIsEnabled(tap: machPort) != isEnabled {
        CGEvent.tapEnable(tap: machPort, enable: isEnabled)
      }

      if isEnabled, !isActive {
        restoreTap()
      }
    }
  }

  var isActive: Bool { machPort.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
  var isMachPortValid: Bool { machPort.map { CFMachPortIsValid($0) } ?? false }

  private static let restoreTriggers: [(center: NotificationCenter, name: Notification.Name)] = [
    (NSWorkspace.shared.notificationCenter, NSWorkspace.screensDidWakeNotification),
    (NSWorkspace.shared.notificationCenter, NSWorkspace.sessionDidBecomeActiveNotification),
    (DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"))
  ]

  private let location: CGEventTapLocation
  private let options: CGEventTapOptions
  private let eventMask: CGEventMask
  private var machPort: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var restoreTriggerObservationTask: Task<Void, Never>?

  convenience init(location: CGEventTapLocation, filtering eventTypes: [CGEventType]) throws {
    try self.init(location: location, options: .defaultTap, eventTypes: eventTypes)
  }

  convenience init(location: CGEventTapLocation, observing eventTypes: [CGEventType]) throws {
    try self.init(location: location, options: .listenOnly, eventTypes: eventTypes)
  }

  private init(location: CGEventTapLocation, options: CGEventTapOptions, eventTypes: [CGEventType]) throws {
    try AccessibilityPermission.ensureGranted()

    self.location = location
    self.options = options
    self.eventMask = CGEventMask(eventTypes.reduce(0) { $0 | (1 << $1.rawValue) })

    try createTap()

    self.restoreTriggerObservationTask = Task {
      await withDiscardingTaskGroup { [weak self] group in
        for restoreTrigger in Self.restoreTriggers {
          group.addTask {
            for await _ in restoreTrigger.center.notifications(named: restoreTrigger.name) {
              await self?.restoreTapIfNeeded()
            }
          }
        }
      }
    }
  }

  isolated deinit {
    restoreTriggerObservationTask?.cancel()
    destroyTap()
  }

  private func createTap() throws {
    destroyTap()

    guard
      let machPort = CGEvent.tapCreate(
        tap: location,
        place: .headInsertEventTap,
        options: options,
        eventsOfInterest: eventMask,
        callback: { _, _, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }

          return MainActor.assumeIsolated {
            Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue().handleEvent(event)
          }
            ? nil
            : Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, machPort, 0) else {
      CFMachPortInvalidate(machPort)
      throw Error.failedToCreateRunLoopSource
    }

    CGEvent.tapEnable(tap: machPort, enable: isEnabled)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

    self.machPort = machPort
    self.runLoopSource = runLoopSource
  }

  private func destroyTap() {
    if let machPort, let runLoopSource {
      if CGEvent.tapIsEnabled(tap: machPort) {
        CGEvent.tapEnable(tap: machPort, enable: false)
      }

      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFMachPortInvalidate(machPort)
    }

    self.machPort = nil
    self.runLoopSource = nil
  }

  private func restoreTapIfNeeded() {
    if isEnabled, !isActive {
      restoreTap()
    }
  }

  private func restoreTap() {
    if let machPort, CFMachPortIsValid(machPort) {
      CGEvent.tapEnable(tap: machPort, enable: true)

      if isActive {
        Log.info("Event tap re-enabled.")
        interruptionHandler?()

        return
      }
    }

    do {
      try createTap()
    } catch {
      Log.error("Failed to recreate event tap: \(error.localizedDescription)")
      return
    }

    guard isActive else {
      Log.error("Recreated event tap is not active.")
      return
    }

    Log.info("Event tap recreated.")
    interruptionHandler?()
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    switch event.type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let machPort, isEnabled {
        CGEvent.tapEnable(tap: machPort, enable: true)
      }

      if isEnabled, !isActive {
        Log.info("Event tap disabled (\(event.type == .tapDisabledByTimeout ? "timeout" : "user input")).")

        Task { [weak self] in
          self?.restoreTapIfNeeded()
        }
      }

      interruptionHandler?()

      return false

    default:
      eventObserver?(event)
      return eventHandler?(event) == true && options != .listenOnly
    }
  }
}
