import AppKit

struct Constants {
  static let overlayColor = NSColor.black.withAlphaComponent(0.1)
  static let selectionColor = NSColor.systemRed.withAlphaComponent(0.15)
  static let guideColor = NSColor.systemRed
  static let labelMargin = CGFloat(5)
  static let labelHorizontalPadding = CGFloat(4)
  static let labelVerticalPadding = CGFloat(2)
  static let labelFontSize = CGFloat(11)
  static let labelFontWeight = NSFont.Weight.medium
  static let labelCornerRadius = CGFloat(4)
  static let labelBackgroundColor = NSColor.systemRed
  static let labelForegroundColor = NSColor.white
}

struct Measurement {
  let startPoint: NSPoint
  let endPoint: NSPoint

  var selection: NSRect {
    return NSRect(x: startPoint.x, y: startPoint.y, width: endPoint.x - startPoint.x, height: endPoint.y - startPoint.y)
      .offsetBy(dx: -1, dy: 0) // Visually center origin with crosshair mouse cursor
      .integral
  }
}

enum LabelPosition {
  case top
  case bottom
  case left
  case right
}

class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool {
    return true
  }
}

class MeasurementView: NSView {
  private var trackingArea: NSTrackingArea?
  private var measurement: Measurement?

  override var acceptsFirstResponder: Bool {
    return true
  }

  override func updateTrackingAreas() {
    if let existingArea = trackingArea {
      removeTrackingArea(existingArea)
    }

    let newArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate],
      owner: self,
      userInfo: nil)
    trackingArea = newArea
    addTrackingArea(newArea)
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.crosshair.set()
  }

  override func mouseDown(with event: NSEvent) {
    let mouseLocation = event.locationInWindow

    if let selection = measurement?.selection {
      let pasteboard = NSPasteboard.general
      let result = "\(Int(selection.width)) × \(Int(selection.height))"
      pasteboard.clearContents()
      pasteboard.setString(result, forType: .string)
      print(result)
      NSApplication.shared.terminate(nil)
    } else {
      measurement = Measurement(startPoint: mouseLocation, endPoint: mouseLocation)
      needsDisplay = true
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard let existingMeasurement = measurement else { return }
    measurement = Measurement(startPoint: existingMeasurement.startPoint, endPoint: event.locationInWindow)
    needsDisplay = true
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { // Escape
      if measurement != nil {
        measurement = nil
        needsDisplay = true
      } else {
        NSApplication.shared.terminate(nil)
      }
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let measurement else { return }
    let isMeasuringRight = measurement.endPoint.x >= measurement.startPoint.x
    let isMeasuringUp = measurement.endPoint.y >= measurement.startPoint.y
    let selectionRect = measurement.selection
    let guideRect = selectionRect.insetBy(dx: 0.5, dy: 0.5)
    let guideOrigin = CGPoint(
      x: isMeasuringRight ? guideRect.minX : guideRect.maxX,
      y: isMeasuringUp ? guideRect.minY : guideRect.maxY)
    let guidePath = NSBezierPath()

    Constants.selectionColor.setFill()
    selectionRect.fill()

    guidePath.lineWidth = 1
    guidePath.move(to: NSPoint(x: selectionRect.minX, y: guideOrigin.y))
    guidePath.line(to: NSPoint(x: selectionRect.maxX, y: guideOrigin.y))
    guidePath.move(to: NSPoint(x: guideOrigin.x, y: selectionRect.minY))
    guidePath.line(to: NSPoint(x: guideOrigin.x, y: selectionRect.maxY))
    Constants.guideColor.setStroke()
    guidePath.stroke()

    drawLabel(
      text: String(Int(selectionRect.width)),
      at: selectionRect,
      position: isMeasuringUp ? .bottom : .top)
    drawLabel(
      text: String(Int(selectionRect.height)),
      at: selectionRect,
      position: isMeasuringRight ? .left : .right)
  }

  private func drawLabel(text: String, at rect: NSRect, position: LabelPosition) {
    let stringAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: Constants.labelFontSize, weight: Constants.labelFontWeight),
      .foregroundColor: Constants.labelForegroundColor
    ]
    let string = NSAttributedString(string: text, attributes: stringAttributes)
    let stringSize = string.size()
    let backgroundSize = NSSize(
      width: stringSize.width + Constants.labelHorizontalPadding * 2,
      height: stringSize.height + Constants.labelVerticalPadding * 2)
    let labelOrigin =
      switch position {
      case .top:
        CGPoint(x: rect.midX - backgroundSize.width / 2, y: rect.maxY + Constants.labelMargin)
      case .bottom:
        CGPoint(x: rect.midX - backgroundSize.width / 2, y: rect.minY - backgroundSize.height - Constants.labelMargin)
      case .left:
        CGPoint(x: rect.minX - backgroundSize.width - Constants.labelMargin, y: rect.midY - backgroundSize.height / 2)
      case .right:
        CGPoint(x: rect.maxX + Constants.labelMargin, y: rect.midY - backgroundSize.height / 2)
      }
    let backgroundRect = NSRect(origin: labelOrigin, size: backgroundSize)
    let backgroundPath = NSBezierPath(
      roundedRect: backgroundRect,
      xRadius: Constants.labelCornerRadius,
      yRadius: Constants.labelCornerRadius)

    Constants.labelBackgroundColor.setFill()
    backgroundPath.fill()

    string.draw(
      at: NSPoint(
        x: backgroundRect.minX + Constants.labelHorizontalPadding,
        y: backgroundRect.minY + Constants.labelVerticalPadding))
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  private var screen: NSScreen!
  private var window: OverlayWindow!
  private var measurementView: MeasurementView!
  private var observers: [(token: NSObjectProtocol, center: NotificationCenter)] = []

  func applicationDidFinishLaunching(_ notification: Notification) {
    screen =
      NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
      ?? NSScreen.main
      ?? NSScreen.screens.first!
    window = OverlayWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
    measurementView = MeasurementView()

    window.level = .screenSaver
    window.collectionBehavior = [.ignoresCycle, .stationary, .auxiliary, .canJoinAllSpaces]
    window.backgroundColor = Constants.overlayColor
    window.contentView = measurementView
    window.setFrame(screen.frame, display: true)
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(measurementView)
    NSApplication.shared.activate(ignoringOtherApps: true)

    let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    let activeSpaceObservationToken = workspaceNotificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { _ in
      NSApplication.shared.activate(ignoringOtherApps: true)
    }
    observers.append((activeSpaceObservationToken, workspaceNotificationCenter))

    let notificationCenter = NotificationCenter.default
    let screenParametersObservationToken = notificationCenter.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      guard let self else { return }
      window.setFrame(screen.frame, display: true)
    }
    observers.append((screenParametersObservationToken, notificationCenter))
  }

  func applicationWillTerminate(_ notification: Notification) {
    observers.forEach { observer in observer.center.removeObserver(observer.token) }
  }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
