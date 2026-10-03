// Shared: Accessibility Agent CGEvent CGEventFlags EventTap Log

import AppKit

enum Configuration {
  static let subsystem = "industries.britown.ScrollToZoom"
  static let modifierKey: CGEventFlags = .maskAlternate
  static let zoomSensitivity = 0.005
}

@MainActor
final class ZoomManager {
  private let startDate = Date.now
  private let modifierFlagsMask = CGEventFlags.modifierFlagsMask.union(.maskSecondaryFn)
  private let modifierKey: CGEventFlags
  private let zoomSensitivity: Double
  private let eventTap: EventTap
  private var isZooming = false

  init(modifierKey: CGEventFlags, zoomSensitivity: Double) throws {
    self.modifierKey = modifierKey
    self.zoomSensitivity = zoomSensitivity
    self.eventTap = try EventTap(location: .cgSessionEventTap, eventTypes: [.scrollWheel])

    eventTap.eventHandler = { [weak self] event in
      self?.handleEvent(event) ?? false
    }

    eventTap.interruptionHandler = { [weak self] in
      guard let self, isZooming else {
        return
      }

      self.isZooming = false

      postZoomGestureEvent(withPhase: .cancelled)
    }

    eventTap.isEnabled = true
  }

  isolated deinit {
    if isZooming {
      postZoomGestureEvent(withPhase: .cancelled)
    }
  }

  func logDiagnosticReport() {
    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Accessibility permission: \(AccessibilityPermission.isGranted)
        Event tap active: \(eventTap.isActive)
        Zooming: \(isZooming)
        Modifier key: \(modifierKey.rawValue)
        Zoom sensitivity: \(zoomSensitivity)
      """
    )
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    guard event.type == .scrollWheel else {
      return false
    }

    guard event.flags.intersection(modifierFlagsMask) == modifierKey else {
      if isZooming {
        self.isZooming = false
        postZoomGestureEvent(withPhase: .cancelled)

        if event.scrollPhase == .changed {
          event.scrollPhase = .began
        }
      }

      return false
    }

    guard let scrollPhase = event.scrollPhase else {
      return false
    }

    switch scrollPhase {
    case .began where !isZooming:
      self.isZooming = true
      postZoomGestureEvent(withPhase: .began)

    case .changed:
      let wasZooming = isZooming

      if !isZooming {
        self.isZooming = true

        event.scrollPhase = .cancelled
        postZoomGestureEvent(withPhase: .began)
      }

      postZoomGestureEvent(
        withPhase: .changed,
        zoomValue: -(Double(event.scrollWheelEventPointDeltaAxis1) * zoomSensitivity)
      )

      return wasZooming

    case .cancelled where isZooming:
      self.isZooming = false
      postZoomGestureEvent(withPhase: .cancelled)

    case .ended where isZooming:
      self.isZooming = false
      postZoomGestureEvent(withPhase: .ended)

    default:
      break
    }

    return true
  }

  private func postZoomGestureEvent(withPhase phase: CGGesturePhase, zoomValue: Double = 0.0) {
    guard let event = CGEvent(source: nil) else {
      Log.error("Failed to create CGEvent for zoom gesture.")
      return
    }

    event.type = .gesture
    event.gestureHIDType = .zoom
    event.gesturePhase = phase
    event.gestureZoomValue = zoomValue
    event.post(tap: .cghidEventTap)
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var zoomManager: ZoomManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    do {
      self.zoomManager = try ZoomManager(
        modifierKey: Configuration.modifierKey,
        zoomSensitivity: Configuration.zoomSensitivity
      )
    } catch {
      Log.error(error.localizedDescription)
      exit(EXIT_FAILURE)
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.zoomManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .printLog: zoomManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case printLog = "print-log"
  case quit
}

@main
enum ScrollToZoom {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .prohibited) {
      AppDelegate()
    }
  }
}
