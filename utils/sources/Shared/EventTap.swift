// Shared: Accessibility

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
    }
  }

  var isActive: Bool { machPort.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

  private let options: CGEventTapOptions
  private var machPort: CFMachPort?
  private var runLoopSource: CFRunLoopSource?

  init(location: CGEventTapLocation, options: CGEventTapOptions = .defaultTap, eventTypes: [CGEventType]) throws {
    try AccessibilityPermission.ensureGranted()

    self.options = options

    guard
      let machPort = CGEvent.tapCreate(
        tap: location,
        place: .headInsertEventTap,
        options: options,
        eventsOfInterest: CGEventMask(eventTypes.reduce(0) { $0 | (1 << $1.rawValue) }),
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

    CGEvent.tapEnable(tap: machPort, enable: false)
    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)

    self.machPort = machPort
    self.runLoopSource = runLoopSource
  }

  isolated deinit {
    if let machPort, let runLoopSource {
      if CGEvent.tapIsEnabled(tap: machPort) {
        CGEvent.tapEnable(tap: machPort, enable: false)
      }

      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFMachPortInvalidate(machPort)
    }
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    switch event.type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
      if let machPort, isEnabled {
        CGEvent.tapEnable(tap: machPort, enable: true)
      }

      interruptionHandler?()

      return false

    default:
      eventObserver?(event)
      return eventHandler?(event) == true && options != .listenOnly
    }
  }
}
