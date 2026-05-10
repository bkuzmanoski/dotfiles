import AppKit

struct Constants {
  static let overlayColor: NSColor = .black.withAlphaComponent(0.1)
  static let selectionColor: NSColor = .systemRed.withAlphaComponent(0.15)
  static let guideColor: NSColor = .systemRed
  static let labelMargin: CGFloat = 5.0
  static let labelHorizontalPadding: CGFloat = 4.0
  static let labelVerticalPadding: CGFloat = 2.0
  static let labelFontSize: CGFloat = 11.0
  static let labelFontWeight: NSFont.Weight = .medium
  static let labelCornerRadius: CGFloat = 4.0
  static let labelBackgroundColor: NSColor = .systemRed
  static let labelForegroundColor: NSColor = .white
}

extension NSScreen {
  static var current: NSScreen? { screens.first(where: { $0.containsMouse }) ?? main }

  var containsMouse: Bool { frame.contains(NSEvent.mouseLocation) }
}

struct Measurement {
  let startPoint: NSPoint
  let endPoint: NSPoint

  var selection: NSRect {
    NSRect(x: startPoint.x, y: startPoint.y, width: endPoint.x - startPoint.x, height: endPoint.y - startPoint.y)
      .integral
  }
}

enum LabelPosition {
  case leading
  case trailing
  case top
  case bottom
}

final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

final class MeasurementView: NSView {
  private var trackingArea: NSTrackingArea?
  private var measurement: Measurement?

  override var acceptsFirstResponder: Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    DispatchQueue.main.async { [weak self] in
      self?.updateTrackingAreas()
    }
  }

  override func updateTrackingAreas() {
    if let trackingArea {
      removeTrackingArea(trackingArea)
    }

    let newTrackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate],
      owner: self,
      userInfo: nil
    )

    self.trackingArea = newTrackingArea

    addTrackingArea(newTrackingArea)
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.crosshair.set()
  }

  override func mouseDown(with event: NSEvent) {
    if let selection = measurement?.selection {
      let pasteboard = NSPasteboard.general
      let result = "\(Int(selection.width)) × \(Int(selection.height))"

      pasteboard.clearContents()
      pasteboard.setString(result, forType: .string)

      print(result)

      NSApplication.shared.terminate(nil)
    } else {
      let mouseLocation = event.locationInWindow

      self.measurement = Measurement(startPoint: mouseLocation, endPoint: mouseLocation)
      self.needsDisplay = true
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard let measurement else {
      return
    }

    self.measurement = Measurement(startPoint: measurement.startPoint, endPoint: event.locationInWindow)
    self.needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    guard event.keyCode == 53 else {
      return
    }

    if measurement != nil {
      self.measurement = nil
      self.needsDisplay = true
    } else {
      NSApplication.shared.terminate(nil)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let measurement else {
      return
    }

    let isMeasuringRight = measurement.endPoint.x >= measurement.startPoint.x
    let isMeasuringUp = measurement.endPoint.y >= measurement.startPoint.y
    let selectionRect = measurement.selection

    Constants.selectionColor.setFill()
    selectionRect.fill()

    let guideRect = selectionRect.insetBy(dx: 0.5, dy: 0.5)
    let guideOrigin = CGPoint(
      x: isMeasuringRight ? guideRect.minX : guideRect.maxX,
      y: isMeasuringUp ? guideRect.minY : guideRect.maxY
    )

    let guidePath = NSBezierPath()
    guidePath.lineWidth = 1

    guidePath.move(to: NSPoint(x: selectionRect.minX, y: guideOrigin.y))
    guidePath.line(to: NSPoint(x: selectionRect.maxX, y: guideOrigin.y))

    guidePath.move(to: NSPoint(x: guideOrigin.x, y: selectionRect.minY))
    guidePath.line(to: NSPoint(x: guideOrigin.x, y: selectionRect.maxY))

    Constants.guideColor.setStroke()
    guidePath.stroke()

    drawLabel(String(Int(selectionRect.width)), for: selectionRect, position: isMeasuringUp ? .bottom : .top)
    drawLabel(String(Int(selectionRect.height)), for: selectionRect, position: isMeasuringRight ? .leading : .trailing)
  }

  private func drawLabel(_ text: String, for rect: NSRect, position: LabelPosition) {
    let attributedString = NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.systemFont(ofSize: Constants.labelFontSize, weight: Constants.labelFontWeight),
        .foregroundColor: Constants.labelForegroundColor
      ]
    )
    let attributedStringSize = attributedString.size()
    let backgroundSize = NSSize(
      width: attributedStringSize.width + Constants.labelHorizontalPadding * 2,
      height: attributedStringSize.height + Constants.labelVerticalPadding * 2
    )

    let labelOrigin: CGPoint

    switch position {
    case .leading:
      labelOrigin = CGPoint(
        x: rect.minX - backgroundSize.width - Constants.labelMargin,
        y: rect.midY - backgroundSize.height / 2
      )

    case .trailing:
      labelOrigin = CGPoint(x: rect.maxX + Constants.labelMargin, y: rect.midY - backgroundSize.height / 2)

    case .top:
      labelOrigin = CGPoint(x: rect.midX - backgroundSize.width / 2, y: rect.maxY + Constants.labelMargin)

    case .bottom:
      labelOrigin = CGPoint(
        x: rect.midX - backgroundSize.width / 2,
        y: rect.minY - backgroundSize.height - Constants.labelMargin
      )
    }

    let backgroundRect = NSRect(origin: labelOrigin, size: backgroundSize)
    let backgroundPath = NSBezierPath(
      roundedRect: backgroundRect,
      xRadius: Constants.labelCornerRadius,
      yRadius: Constants.labelCornerRadius
    )

    Constants.labelBackgroundColor.setFill()
    backgroundPath.fill()

    attributedString.draw(
      at: NSPoint(
        x: backgroundRect.minX + Constants.labelHorizontalPadding,
        y: backgroundRect.minY + Constants.labelVerticalPadding
      )
    )
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var observers: [(token: NSObjectProtocol, notificationCenter: NotificationCenter)] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApplication.shared.activate(ignoringOtherApps: true)

    guard let screenScreen = NSScreen.current else {
      FileHandle.standardError.write(Data("No screen detected.\n".utf8))
      NSApplication.shared.terminate(nil)

      return
    }

    let window = OverlayWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    window.level = .screenSaver
    window.collectionBehavior = [.ignoresCycle, .stationary, .auxiliary, .canJoinAllSpaces]
    window.backgroundColor = Constants.overlayColor
    window.contentView = MeasurementView()
    window.setFrame(screenScreen.frame, display: true)
    window.makeKeyAndOrderFront(nil)

    let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    let activeSpaceObservationToken = workspaceNotificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    self.observers.append((activeSpaceObservationToken, workspaceNotificationCenter))

    let notificationCenter = NotificationCenter.default
    let screenParametersObservationToken = notificationCenter.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { _ in
      guard let currentScreen = NSScreen.current, window.frame != currentScreen.frame else {
        return
      }

      window.setFrame(currentScreen.frame, display: true)
    }

    self.observers.append((screenParametersObservationToken, notificationCenter))
  }

  func applicationWillTerminate(_ notification: Notification) {
    for observer in observers {
      observer.notificationCenter.removeObserver(observer.token)
    }
  }
}

MainActor.assumeIsolated {
  let delegate = AppDelegate()
  let application = NSApplication.shared
  application.delegate = delegate
  application.setActivationPolicy(.accessory)
  application.run()
}
