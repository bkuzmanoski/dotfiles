import Cocoa
import Foundation

struct Measurement {
  let startPoint: NSPoint
  let endPoint: NSPoint

  var isMovingRight: Bool { endPoint.x >= startPoint.x }
  var isMovingDown: Bool { endPoint.y >= startPoint.y }

  var startX: CGFloat { isMovingRight ? floor(startPoint.x) - 1 : floor(startPoint.x) }
  var startY: CGFloat { isMovingDown ? floor(startPoint.y) : floor(startPoint.y) + 1 }
  var endX: CGFloat { isMovingRight ? floor(endPoint.x) : floor(endPoint.x) - 1 }
  var endY: CGFloat { isMovingDown ? floor(endPoint.y) + 1 : floor(endPoint.y) }

  var selectionFrame: NSRect {
    NSRect(x: min(startX, endX), y: min(startY, endY), width: width, height: height)
  }
  var width: CGFloat { abs(endX - startX) }
  var height: CGFloat { abs(endY - startY) }

  var widthString: String { String(format: "%.0f", width) }
  var heightString: String { String(format: "%.0f", height) }
  var resultString: String { String(format: "%.0f × %.0f", width, height) }
}

class MeasurePixels: NSWindow {
  private var startPoint: NSPoint?
  private var overlay: NSView?
  private var widthLabel: NSTextField?
  private var heightLabel: NSTextField?

  override var canBecomeKey: Bool { true }

  init(for screen: NSScreen) {
    let screenFrame = screen.frame
    super.init(contentRect: screenFrame, styleMask: [.borderless], backing: .buffered, defer: false)

    level = .screenSaver
    backgroundColor = NSColor.black.withAlphaComponent(0.1)
    contentView?.wantsLayer = true
    contentView?.addTrackingArea(
      NSTrackingArea(
        rect: contentView?.bounds ?? .zero,
        options: [.activeAlways, .mouseMoved, .inVisibleRect, .cursorUpdate],
        owner: self,
        userInfo: nil))
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.crosshair.set()
  }

  override func mouseUp(with event: NSEvent) {
    let point = event.locationInWindow
    if startPoint == nil {
      startPoint = point
    } else {
      let measurement = Measurement(startPoint: startPoint!, endPoint: point)
      print(measurement.resultString)
      NSApplication.shared.terminate(nil)
    }
  }

  override func mouseMoved(with event: NSEvent) {
    guard let startPoint = startPoint else { return }

    let measurement = Measurement(startPoint: startPoint, endPoint: event.locationInWindow)
    drawOverlay(for: measurement)
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53:  // Escape
      if startPoint != nil {
        startPoint = nil
        removeOverlay()
      } else {
        NSApplication.shared.terminate(nil)
      }
    default:
      super.keyDown(with: event)
    }
  }

  func drawOverlay(for measurement: Measurement) {
    if overlay == nil {
      overlay = NSView(frame: .zero)
      overlay?.wantsLayer = true
      contentView?.addSubview(overlay!)
    }

    let selectionFrame = measurement.selectionFrame
    overlay?.frame = selectionFrame

    let borderLayer = CAShapeLayer()
    let path = CGMutablePath()

    path.move(to: CGPoint(x: measurement.isMovingRight ? 0.5 : selectionFrame.width - 0.5, y: 0))
    path.addLine(
      to: CGPoint(
        x: measurement.isMovingRight ? 0.5 : selectionFrame.width - 0.5, y: selectionFrame.height))

    path.move(to: CGPoint(x: 0, y: measurement.isMovingDown ? 0.5 : selectionFrame.height - 0.5))
    path.addLine(
      to: CGPoint(
        x: selectionFrame.width, y: measurement.isMovingDown ? 0.5 : selectionFrame.height - 0.5))

    borderLayer.path = path
    borderLayer.strokeColor = NSColor.systemRed.cgColor
    borderLayer.fillColor = nil
    borderLayer.lineWidth = 1

    overlay?.layer?.sublayers?.removeAll()
    overlay?.layer?.addSublayer(borderLayer)
    overlay?.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.15).cgColor

    updateLabels(for: measurement)
  }

  private func updateLabels(for measurement: Measurement) {
    if widthLabel == nil {
      let (label, background) = createLabel(with: measurement.widthString)
      widthLabel = label
      contentView?.addSubview(background)
      background.addSubview(label)
    } else {
      widthLabel?.stringValue = measurement.widthString
    }

    if heightLabel == nil {
      let (label, background) = createLabel(with: measurement.heightString)
      heightLabel = label
      contentView?.addSubview(background)
      background.addSubview(label)
    } else {
      heightLabel?.stringValue = measurement.heightString
    }

    widthLabel?.sizeToFit()
    heightLabel?.sizeToFit()

    positionLabels(for: measurement)
  }

  private func createLabel(with string: String) -> (label: NSTextField, background: NSView) {
    let label = NSTextField(labelWithString: string)
    label.font = .systemFont(ofSize: 11, weight: .medium)
    label.textColor = .white

    let background = NSView()
    background.wantsLayer = true
    background.layer?.cornerRadius = 4
    background.layer?.backgroundColor = NSColor.systemRed.cgColor

    return (label, background)
  }

  private func positionLabels(for measurement: Measurement) {
    let frame = measurement.selectionFrame
    let padding: CGFloat = 2

    if let widthLabel = widthLabel, let widthBackground = widthLabel.superview {
      widthBackground.frame = NSRect(
        x: 0, y: 0,
        width: widthLabel.frame.width + padding * 2, height: widthLabel.frame.height + padding * 2
      )
      widthLabel.frame.origin = NSPoint(x: padding, y: padding)

      let absoluteX = frame.origin.x + (frame.width - widthBackground.frame.width) / 2
      let absoluteY: CGFloat =
        frame.origin.y
        + (measurement.isMovingDown
          ? -widthBackground.frame.height - 5
          : frame.height + 5)
      widthBackground.frame.origin = CGPoint(x: absoluteX, y: absoluteY)
    }

    if let heightLabel = heightLabel, let heightBackground = heightLabel.superview {
      heightBackground.frame = NSRect(
        x: 0, y: 0,
        width: heightLabel.frame.width + padding * 2, height: heightLabel.frame.height + padding * 2
      )
      heightLabel.frame.origin = NSPoint(x: padding, y: padding)

      let absoluteX: CGFloat =
        frame.origin.x
        + (measurement.isMovingRight
          ? -heightBackground.frame.width - 5
          : frame.width + 5)
      let absoluteY = frame.origin.y + (frame.height - heightBackground.frame.height) / 2
      heightBackground.frame.origin = CGPoint(x: absoluteX, y: absoluteY)
    }
  }

  func removeOverlay() {
    overlay?.removeFromSuperview()
    overlay = nil
    widthLabel?.superview?.removeFromSuperview()
    heightLabel?.superview?.removeFromSuperview()
    widthLabel = nil
    heightLabel = nil
  }
}

freopen("/dev/null", "w", stderr)  // Silence logs from Input Method Kit

guard let mainScreen = NSScreen.main else {
  print("Error: Screen unavailable")
  exit(1)
}

NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.activate(ignoringOtherApps: true)

let window = MeasurePixels(for: mainScreen)
window.makeKeyAndOrderFront(nil)
window.makeFirstResponder(window)

NSApplication.shared.run()
