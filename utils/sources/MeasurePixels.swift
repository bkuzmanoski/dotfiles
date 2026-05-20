import ScreenCaptureKit

enum Configuration {
  static let subsystem = "industries.britown.MeasurePixels"
  static let spanMeasurementRGBDifferenceThreshold = 20
  static let overlayWindowBackgroundColor: NSColor = .black.withAlphaComponent(0.1)
  static let selectionColor: NSColor = .systemRed.withAlphaComponent(0.15)
  static let guideLineColor: NSColor = .systemRed
  static let spanMeasurementGuidelineEndCapLength: CGFloat? = 4.0
  static let labelMargin: CGFloat = 6.0
  static let labelHorizontalPadding: CGFloat = 4.0
  static let labelVerticalPadding: CGFloat = 2.0
  static let labelFontSize: CGFloat = 11.0
  static let labelFontWeight: NSFont.Weight = .medium
  static let labelCornerRadius: CGFloat = 4.0
  static let labelBackgroundColor: NSColor = .systemRed
  static let labelForegroundColor: NSColor = .white
}

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connectionID: CGSConnectionID, _ displayIdentifier: CFString?) -> Unmanaged<CFArray>?

typealias DisplayIdentifier = String
typealias SpaceID = UInt64

extension NSScreen {
  static var screenContainingMouse: NSScreen? { screens.first { $0.frame.contains(NSEvent.mouseLocation) } }

  var displayIdentifier: DisplayIdentifier? {
    guard
      let cgDirectDisplayID,
      let uuid = CGDisplayCreateUUIDFromDisplayID(cgDirectDisplayID)?.takeRetainedValue()
    else {
      return nil
    }

    return CFUUIDCreateString(nil, uuid) as DisplayIdentifier
  }

  var currentSpaceID: SpaceID? {
    let cgsConnectionID = CGSMainConnectionID()

    guard
      let displayIdentifier = self.displayIdentifier,
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        cgsConnectionID,
        displayIdentifier as CFString
      )?.takeRetainedValue() as? [[String: Any]],
      let displayInfo = managedDisplaySpaces.first(where: { $0["Display Identifier"] as? String == displayIdentifier }),
      let spacesInfo = displayInfo["Spaces"] as? [[String: Any]],
      !spacesInfo.isEmpty,
      let currentSpaceInfo = displayInfo["Current Space"] as? [String: Any],
      let currentSpaceID = currentSpaceInfo["id64"] as? SpaceID
    else {
      return nil
    }

    return currentSpaceID
  }

  static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
    return screens.first { $0.cgDirectDisplayID == displayID }
  }
}

extension NSCursor {
  static let screenshotSelection: NSCursor? = named("screenshotselection")

  static func named(_ name: String) -> NSCursor? {
    let cursorDirectory = URL(
      fileURLWithPath:
        "/System/Library/Frameworks/ApplicationServices.framework/Versions/A/Frameworks/HIServices.framework/Versions/A/Resources/cursors/\(name)"
    )
    let imageURL = cursorDirectory.appendingPathComponent("cursor.pdf")
    let plistURL = cursorDirectory.appendingPathComponent("info.plist")

    guard
      let image = NSImage(contentsOf: imageURL),
      let plist = NSDictionary(contentsOf: plistURL),
      let hotSpotX = plist["hotx"] as? Double,
      let hotSpotY = plist["hoty"] as? Double
    else {
      return nil
    }

    return NSCursor(image: image, hotSpot: NSPoint(x: hotSpotX, y: hotSpotY))
  }
}

extension CGFloat {
  var compactString: String { Double(self).formatted(.number.precision(.fractionLength(0...2)).grouping(.never)) }
}

enum HorizontalDirection {
  case leading
  case trailing
}

enum VerticalDirection {
  case upward
  case downward
}

enum Axis {
  case horizontal
  case vertical
}

enum Measurement: Equatable {
  case region(RegionMeasurement)
  case span(SpanMeasurement)

  var formattedString: String {
    switch self {
    case .region(let measurement): measurement.formattedString
    case .span(let measurement): measurement.formattedString
    }
  }
}

struct RegionMeasurement: Equatable {
  let startLocation: CGPoint
  let endLocation: CGPoint

  var horizontalDirection: HorizontalDirection { endLocation.x >= startLocation.x ? .trailing : .leading }
  var verticalDirection: VerticalDirection { endLocation.y >= startLocation.y ? .upward : .downward }

  var boundingRect: CGRect {
    CGRect(
      x: startLocation.x,
      y: startLocation.y,
      width: endLocation.x - startLocation.x,
      height: endLocation.y - startLocation.y
    ).integral
  }

  var formattedString: String { "\(boundingRect.width.compactString) × \(boundingRect.height.compactString)" }

  func extended(to endLocation: CGPoint) -> RegionMeasurement {
    return RegionMeasurement(startLocation: self.startLocation, endLocation: endLocation)
  }
}

struct SpanMeasurement: Equatable {
  let referenceLocation: CGPoint
  let axis: Axis
  let startLocation: CGPoint
  let length: CGFloat

  var endLocation: CGPoint {
    switch axis {
    case .horizontal: CGPoint(x: startLocation.x + length, y: startLocation.y)
    case .vertical: CGPoint(x: startLocation.x, y: startLocation.y + length)
    }
  }

  var formattedString: String { "\(length.compactString)" }
}

struct ScreenCapture {
  enum Error: Swift.Error, LocalizedError {
    case unsupportedPixelFormat(
      byteOrder: CGImageByteOrderInfo,
      alphaInfo: CGImageAlphaInfo,
      bitsPerPixel: Int,
      bitsPerComponent: Int
    )
    case missingPixelData

    var errorDescription: String? {
      switch self {
      case .unsupportedPixelFormat(let byteOrder, let alphaInfo, let bitsPerPixel, let bitsPerComponent):
        "Unsupported pixel format: \(byteOrder), \(alphaInfo), \(bitsPerPixel) bits per pixel, \(bitsPerComponent) bits per component."

      case .missingPixelData:
        "Captured image is missing pixel data."
      }
    }
  }

  let displayID: CGDirectDisplayID
  let width: Int
  let height: Int
  let scaleFactor: CGFloat
  let pixelsPerRow: Int

  private let pixelData: CFData
  private let pixelDataPointer: UnsafePointer<UInt8>

  init(image: CGImage, displayID: CGDirectDisplayID, scaleFactor: CGFloat) throws {
    guard
      image.bitmapInfo.byteOrder == .order32Little,
      image.bitmapInfo.alpha == .premultipliedFirst,
      image.bitsPerPixel == 32,
      image.bitsPerComponent == 8
    else {
      throw Error.unsupportedPixelFormat(
        byteOrder: image.bitmapInfo.byteOrder,
        alphaInfo: image.bitmapInfo.alpha,
        bitsPerPixel: image.bitsPerPixel,
        bitsPerComponent: image.bitsPerComponent
      )
    }

    guard
      let pixelData = image.dataProvider?.data,
      let pixelDataPointer = CFDataGetBytePtr(pixelData)
    else {
      throw Error.missingPixelData
    }

    self.displayID = displayID
    self.width = image.width
    self.height = image.height
    self.scaleFactor = scaleFactor
    self.pixelsPerRow = image.bytesPerRow / (image.bitsPerPixel / 8)
    self.pixelData = pixelData
    self.pixelDataPointer = pixelDataPointer
  }

  func withUnsafePixelBuffer<R>(_ body: (UnsafeBufferPointer<UInt32>) throws -> R) rethrows -> R {
    let pixelCount = height * pixelsPerRow

    return try pixelDataPointer.withMemoryRebound(to: UInt32.self, capacity: pixelCount) { pointer in
      let buffer = UnsafeBufferPointer(start: pointer, count: pixelCount)
      return try body(buffer)
    }
  }
}

extension UnsafeBufferPointer where Element == UInt32 {
  func rgbDifference(betweenIndex indexA: Int, andIndex indexB: Int) -> Int {
    let pixelA = self[indexA]
    let pixelB = self[indexB]

    let redA = Int((pixelA >> 16) & 0xFF)
    let greenA = Int((pixelA >> 8) & 0xFF)
    let blueA = Int(pixelA & 0xFF)

    let redB = Int((pixelB >> 16) & 0xFF)
    let greenB = Int((pixelB >> 8) & 0xFF)
    let blueB = Int(pixelB & 0xFF)

    return abs(redA - redB) + abs(greenA - greenB) + abs(blueA - blueB)
  }

  func maxRGBDifference(
    betweenSliceStartingAt startIndexA: Int,
    andSliceStartingAt startIndexB: Int,
    sliceCount: Int,
    stride: Int
  ) -> Int {
    var maxDifference = 0
    var indexA = startIndexA
    var indexB = startIndexB

    for _ in 0..<sliceCount {
      let difference = rgbDifference(betweenIndex: indexA, andIndex: indexB)

      if difference > maxDifference {
        maxDifference = difference
      }

      indexA += stride
      indexB += stride
    }

    return maxDifference
  }
}

enum EdgeDetector {
  static func detect(
    edgesIn screenCapture: ScreenCapture,
    from location: CGPoint,
    alongAxis axis: Axis,
    rgbDifferenceThreshold: Int
  ) -> (startLocation: CGPoint, endLocation: CGPoint, length: CGFloat) {
    let pixelsPerPoint = Int(screenCapture.scaleFactor)

    return screenCapture.withUnsafePixelBuffer { pixelBuffer in
      switch axis {
      case .horizontal:
        let heightInPoints = CGFloat(screenCapture.height) / screenCapture.scaleFactor
        let orthogonalPointY = max(0, min(floor(location.y), heightInPoints - 1))
        let measurementPointX = location.x
        let targetPixelX = Int(floor(measurementPointX * screenCapture.scaleFactor))
        let targetPixelY = Int(CGFloat(screenCapture.height) - (orthogonalPointY + 1) * screenCapture.scaleFactor)
        let clampedPixelX = max(0, min(targetPixelX, screenCapture.width - 1))
        let clampedPixelY = max(0, min(targetPixelY, screenCapture.height - pixelsPerPoint))
        let rowStartBufferIndex = clampedPixelY * screenCapture.pixelsPerRow

        var leadingPixelX = clampedPixelX
        var previousPixelX = clampedPixelX

        for searchPixelX in stride(from: clampedPixelX - 1, through: 0, by: -1) {
          let maxDifference = pixelBuffer.maxRGBDifference(
            betweenSliceStartingAt: rowStartBufferIndex + previousPixelX,
            andSliceStartingAt: rowStartBufferIndex + searchPixelX,
            sliceCount: pixelsPerPoint,
            stride: screenCapture.pixelsPerRow
          )

          if maxDifference > rgbDifferenceThreshold {
            break
          }

          previousPixelX = searchPixelX
          leadingPixelX = searchPixelX
        }

        previousPixelX = clampedPixelX

        var trailingPixelX = clampedPixelX

        for searchPixelX in stride(from: clampedPixelX + 1, to: screenCapture.width, by: 1) {
          let maxRGBDifference = pixelBuffer.maxRGBDifference(
            betweenSliceStartingAt: rowStartBufferIndex + previousPixelX,
            andSliceStartingAt: rowStartBufferIndex + searchPixelX,
            sliceCount: pixelsPerPoint,
            stride: screenCapture.pixelsPerRow
          )

          if maxRGBDifference > rgbDifferenceThreshold {
            break
          }

          previousPixelX = searchPixelX
          trailingPixelX = searchPixelX
        }

        let leadingPointX = CGFloat(leadingPixelX) / screenCapture.scaleFactor
        let trailingPointX = CGFloat(trailingPixelX + 1) / screenCapture.scaleFactor

        return (
          CGPoint(x: leadingPointX, y: orthogonalPointY),
          CGPoint(x: trailingPointX, y: orthogonalPointY),
          trailingPointX - leadingPointX
        )

      case .vertical:
        let widthInPoints = CGFloat(screenCapture.width) / screenCapture.scaleFactor
        let orthogonalPointX = max(0, min(floor(location.x), widthInPoints - 1))
        let measurementPointY = location.y
        let targetPixelX = Int(orthogonalPointX * screenCapture.scaleFactor)
        let targetPixelY = Int(CGFloat(screenCapture.height) - floor(measurementPointY * screenCapture.scaleFactor) - 1)
        let clampedPixelX = max(0, min(targetPixelX, screenCapture.width - pixelsPerPoint))
        let clampedPixelY = max(0, min(targetPixelY, screenCapture.height - 1))
        let columnStartBufferIndex = clampedPixelX

        var topPixelY = clampedPixelY
        var previousPixelY = clampedPixelY

        for searchPixelY in stride(from: clampedPixelY - 1, through: 0, by: -1) {
          let maxDifference = pixelBuffer.maxRGBDifference(
            betweenSliceStartingAt: previousPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            andSliceStartingAt: searchPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            sliceCount: pixelsPerPoint,
            stride: 1
          )

          if maxDifference > rgbDifferenceThreshold {
            break
          }

          previousPixelY = searchPixelY
          topPixelY = searchPixelY
        }

        previousPixelY = clampedPixelY

        var bottomPixelY = clampedPixelY

        for searchPixelY in stride(from: clampedPixelY + 1, to: screenCapture.height, by: 1) {
          let maxRGBDifference = pixelBuffer.maxRGBDifference(
            betweenSliceStartingAt: previousPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            andSliceStartingAt: searchPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            sliceCount: pixelsPerPoint,
            stride: 1
          )

          if maxRGBDifference > rgbDifferenceThreshold {
            break
          }

          previousPixelY = searchPixelY
          bottomPixelY = searchPixelY
        }

        let topPointY = CGFloat(screenCapture.height - topPixelY) / screenCapture.scaleFactor
        let bottomPointY = CGFloat(screenCapture.height - bottomPixelY - 1) / screenCapture.scaleFactor

        return (
          CGPoint(x: orthogonalPointX, y: bottomPointY),
          CGPoint(x: orthogonalPointX, y: topPointY),
          topPointY - bottomPointY
        )
      }
    }
  }
}

enum ScreenCaptureService {
  enum Error: Swift.Error, LocalizedError {
    case screenNotFound(CGDirectDisplayID)
    case displayNotFound
    case missingSdrImage

    var errorDescription: String? {
      switch self {
      case .screenNotFound(let displayID): "Screen for display ID \(displayID) not found."
      case .displayNotFound: "Display not found in shareable content."
      case .missingSdrImage: "Captured screenshot is missing SDR image representation."
      }
    }
  }

  nonisolated static func capture(displayID: CGDirectDisplayID) async throws -> ScreenCapture {
    let availableContent = try await SCShareableContent.current

    guard let screen = NSScreen.screen(for: displayID) else {
      throw Error.screenNotFound(displayID)
    }

    guard let display = availableContent.displays.first(where: { $0.displayID == displayID }) else {
      throw Error.displayNotFound
    }

    let contentFilter = SCContentFilter(
      display: display,
      including: availableContent.applications.filter { application in
        application.processID != NSRunningApplication.current.processIdentifier
      },
      exceptingWindows: []
    )
    let configuration = SCScreenshotConfiguration()
    configuration.dynamicRange = .sdr
    configuration.displayIntent = .canonical
    configuration.ignoreShadows = false
    configuration.showsCursor = false

    let screenshot: SCScreenshotOutput = try await SCScreenshotManager.captureScreenshot(
      contentFilter: contentFilter,
      configuration: configuration
    )

    guard let image = screenshot.sdrImage else {
      throw Error.missingSdrImage
    }

    let screenCapture = try ScreenCapture(image: image, displayID: displayID, scaleFactor: screen.backingScaleFactor)

    return screenCapture
  }
}

enum MeasurementRenderer {
  private enum LabelPlacement {
    case leading
    case trailing
    case top
    case bottom

    var opposite: LabelPlacement {
      switch self {
      case .leading: .trailing
      case .trailing: .leading
      case .top: .bottom
      case .bottom: .top
      }
    }

    func backgroundRect(at anchor: CGPoint, size: CGSize, margin: CGFloat, within bounds: CGRect) -> CGRect {
      var x: CGFloat
      var y: CGFloat

      switch self {
      case .leading:
        x = anchor.x - size.width - margin

        if x < bounds.minX {
          x = anchor.x + margin
        }

        y = anchor.y - size.height / 2

      case .trailing:
        x = anchor.x + margin

        if x + size.width > bounds.maxX {
          x = anchor.x - size.width - margin
        }

        y = anchor.y - size.height / 2

      case .top:
        x = anchor.x - size.width / 2
        y = anchor.y + margin

        if y + size.height > bounds.maxY {
          y = anchor.y - size.height - margin
        }

      case .bottom:
        x = anchor.x - size.width / 2
        y = anchor.y - size.height - margin

        if y < bounds.minY {
          y = anchor.y + margin
        }
      }

      let clampedX = max(bounds.minX + margin, min(x, bounds.maxX - size.width - margin))
      let clampedY = max(bounds.minY + margin, min(y, bounds.maxY - size.height - margin))

      return CGRect(x: clampedX, y: clampedY, width: size.width, height: size.height)
    }
  }

  static func draw(measurement: Measurement, in frame: CGRect) {
    switch measurement {
    case .region(let regionMeasurement): drawRegionMeasurement(regionMeasurement, in: frame)
    case .span(let spanMeasurement): drawSpanMeasurement(spanMeasurement, in: frame)
    }
  }

  private static func drawRegionMeasurement(_ measurement: RegionMeasurement, in bounds: CGRect) {
    let rect = measurement.boundingRect

    Configuration.selectionColor.setFill()
    rect.fill()

    let insetRect = rect.insetBy(dx: 0.5, dy: 0.5)
    let guideLineOriginX = measurement.horizontalDirection == .trailing ? insetRect.minX : insetRect.maxX
    let guideLineOriginY = measurement.verticalDirection == .upward ? insetRect.minY : insetRect.maxY
    let guideLinePath = NSBezierPath()
    guideLinePath.lineWidth = 1
    guideLinePath.move(to: NSPoint(x: rect.minX, y: guideLineOriginY))
    guideLinePath.line(to: NSPoint(x: rect.maxX, y: guideLineOriginY))
    guideLinePath.move(to: NSPoint(x: guideLineOriginX, y: rect.minY))
    guideLinePath.line(to: NSPoint(x: guideLineOriginX, y: rect.maxY))

    Configuration.guideLineColor.setStroke()
    guideLinePath.stroke()

    let horizontalMidPoint = CGPoint(x: insetRect.midX, y: guideLineOriginY)
    let verticalMidPoint = CGPoint(x: guideLineOriginX, y: insetRect.midY)

    drawLabel(
      rect.width.compactString,
      at: horizontalMidPoint,
      margin: Configuration.labelMargin,
      placement: measurement.verticalDirection == .upward ? .bottom : .top,
      inBounds: bounds
    )
    drawLabel(
      rect.height.compactString,
      at: verticalMidPoint,
      margin: Configuration.labelMargin,
      placement: measurement.horizontalDirection == .trailing ? .leading : .trailing,
      inBounds: bounds
    )
  }

  private static func drawSpanMeasurement(_ measurement: SpanMeasurement, in bounds: CGRect) {
    let startPoint = NSPoint(
      x: measurement.axis == .vertical ? measurement.startLocation.x + 0.5 : measurement.startLocation.x,
      y: measurement.axis == .horizontal ? measurement.startLocation.y + 0.5 : measurement.startLocation.y
    )
    let endPoint = NSPoint(
      x: measurement.axis == .vertical ? measurement.endLocation.x + 0.5 : measurement.endLocation.x,
      y: measurement.axis == .horizontal ? measurement.endLocation.y + 0.5 : measurement.endLocation.y
    )
    let guideLinePath = NSBezierPath()
    guideLinePath.lineWidth = 1
    guideLinePath.move(to: startPoint)
    guideLinePath.line(to: endPoint)

    if let guideLineEndCapLength = Configuration.spanMeasurementGuidelineEndCapLength,
      measurement.length > guideLineEndCapLength
    {
      switch measurement.axis {
      case .horizontal:
        guideLinePath.move(to: NSPoint(x: startPoint.x + 0.5, y: startPoint.y - guideLineEndCapLength))
        guideLinePath.line(to: NSPoint(x: startPoint.x + 0.5, y: startPoint.y + guideLineEndCapLength))
        guideLinePath.move(to: NSPoint(x: endPoint.x - 0.5, y: endPoint.y - guideLineEndCapLength))
        guideLinePath.line(to: NSPoint(x: endPoint.x - 0.5, y: endPoint.y + guideLineEndCapLength))

      case .vertical:
        guideLinePath.move(to: NSPoint(x: startPoint.x - guideLineEndCapLength, y: startPoint.y + 0.5))
        guideLinePath.line(to: NSPoint(x: startPoint.x + guideLineEndCapLength, y: startPoint.y + 0.5))
        guideLinePath.move(to: NSPoint(x: endPoint.x - guideLineEndCapLength, y: endPoint.y - 0.5))
        guideLinePath.line(to: NSPoint(x: endPoint.x + guideLineEndCapLength, y: endPoint.y - 0.5))
      }
    }

    Configuration.guideLineColor.setStroke()
    guideLinePath.stroke()

    let midPoint = CGPoint(x: floor((startPoint.x + endPoint.x) / 2), y: floor((startPoint.y + endPoint.y) / 2))

    drawLabel(
      measurement.length.compactString,
      at: midPoint,
      margin: Configuration.labelMargin,
      placement: measurement.axis == .horizontal ? .bottom : .trailing,
      inBounds: bounds
    )
  }

  private static func drawLabel(
    _ text: String,
    at anchor: CGPoint,
    margin: CGFloat,
    placement preferredPlacement: LabelPlacement,
    inBounds bounds: CGRect
  ) {
    let attributedString = NSAttributedString(
      string: text,
      attributes: [
        .font: NSFont.monospacedDigitSystemFont(
          ofSize: Configuration.labelFontSize,
          weight: Configuration.labelFontWeight
        ),
        .foregroundColor: Configuration.labelForegroundColor
      ]
    )
    let textSize = attributedString.size()
    let backgroundSize = CGSize(
      width: ceil(textSize.width) + Configuration.labelHorizontalPadding * 2,
      height: ceil(textSize.height) + Configuration.labelVerticalPadding * 2
    )
    let backgroundRect = preferredPlacement.backgroundRect(
      at: anchor,
      size: backgroundSize,
      margin: margin,
      within: bounds
    )
    let backgroundPath = NSBezierPath(
      roundedRect: backgroundRect,
      xRadius: Configuration.labelCornerRadius,
      yRadius: Configuration.labelCornerRadius
    )

    Configuration.labelBackgroundColor.setFill()
    backgroundPath.fill()

    attributedString.draw(
      at: CGPoint(
        x: backgroundRect.minX + Configuration.labelHorizontalPadding,
        y: backgroundRect.minY + Configuration.labelVerticalPadding
      )
    )
  }
}

final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

@MainActor
protocol MeasurementViewDelegate: AnyObject {
  func measurementView(_ view: MeasurementView, didReceive event: MeasurementView.Event)
}

@MainActor
final class MeasurementView: NSView {
  enum Event {
    case mouseMoved(CGPoint)
    case mouseDown(CGPoint)
    case flagsChanged(NSEvent.ModifierFlags)
    case keyDown(UInt16)
  }

  weak var delegate: MeasurementViewDelegate?

  var measurements: [Measurement] = []

  override var acceptsFirstResponder: Bool { true }

  private var mouseTrackingArea: NSTrackingArea?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    DispatchQueue.main.async {
      NSCursor.screenshotSelection?.set()
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let mouseTrackingArea {
      removeTrackingArea(mouseTrackingArea)
    }

    let mouseTrackingArea = NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
      owner: self,
      userInfo: nil
    )

    addTrackingArea(mouseTrackingArea)

    self.mouseTrackingArea = mouseTrackingArea
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.screenshotSelection?.set()
  }

  override func mouseMoved(with event: NSEvent) {
    NSCursor.screenshotSelection?.set()
    delegate?.measurementView(self, didReceive: .mouseMoved(event.locationInWindow))
  }

  override func mouseDown(with event: NSEvent) {
    delegate?.measurementView(self, didReceive: .mouseDown(event.locationInWindow))
  }

  override func flagsChanged(with event: NSEvent) {
    delegate?.measurementView(self, didReceive: .flagsChanged(event.modifierFlags))
  }

  override func keyDown(with event: NSEvent) {
    delegate?.measurementView(self, didReceive: .keyDown(event.keyCode))
  }

  override func draw(_ dirtyRect: NSRect) {
    for measurement in measurements {
      MeasurementRenderer.draw(measurement: measurement, in: self.bounds)
    }
  }
}

enum AppMode: String {
  case single
  case continuous

  var overlayWindowBackgroundColor: NSColor {
    switch self {
    case .single: Configuration.overlayWindowBackgroundColor
    case .continuous: .clear
    }
  }
}

@MainActor
final class MeasurementSession {
  enum Error: Swift.Error, LocalizedError {
    case screenCapturePermissionNotGranted
    case failedToDetermineDisplayID
    case failedToDetermineSpaceID

    var errorDescription: String? {
      switch self {
      case .screenCapturePermissionNotGranted: "Screen capture permission not granted."
      case .failedToDetermineDisplayID: "Failed to determine display ID for the specified screen."
      case .failedToDetermineSpaceID: "Failed to determine current space ID for the specified screen."
      }
    }
  }

  private enum MeasurementMode: Equatable {
    case region
    case span(Axis)

    var isSpan: Bool {
      switch self {
      case .region: false
      case .span: true
      }
    }
  }

  private let measurementView = MeasurementView()
  private let overlayWindow: OverlayWindow
  private var displayID: CGDirectDisplayID
  private var currentSpaceID: SpaceID
  private var appMode: AppMode
  private var workspaceObservationTask: Task<Void, Never>?
  private var screenCaptureTask: Task<Void, Never>?
  private var screenCapture: ScreenCapture?
  private var measurementMode: MeasurementMode = .region

  private var activeMeasurement: Measurement? {
    didSet {
      updateMeasurementView()
    }
  }

  private var committedMeasurements: [Measurement] = [] {
    didSet {
      updateMeasurementView()
    }
  }

  private var lastMouseLocation: CGPoint?
  private var lastRegionMeasurement: RegionMeasurement?

  private var mouseLocation: CGPoint? {
    lastMouseLocation
      ?? (NSScreen.screen(for: displayID)?.frame.contains(NSEvent.mouseLocation) ?? false
        ? NSEvent.mouseLocation
        : nil)
  }

  init(screen: NSScreen, appMode: AppMode) throws {
    guard CGPreflightScreenCaptureAccess() else {
      throw Error.screenCapturePermissionNotGranted
    }

    guard let displayID = screen.cgDirectDisplayID else {
      throw Error.failedToDetermineDisplayID
    }

    guard let currentSpaceID = screen.currentSpaceID else {
      throw Error.failedToDetermineSpaceID
    }

    let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = measurementView
    window.collectionBehavior = [.ignoresCycle, .stationary, .auxiliary, .canJoinAllSpaces]
    window.level = .screenSaver
    window.backgroundColor = appMode.overlayWindowBackgroundColor
    window.ignoresMouseEvents = false

    self.overlayWindow = window
    self.displayID = displayID
    self.currentSpaceID = currentSpaceID
    self.appMode = appMode
    self.workspaceObservationTask = Task {
      await withDiscardingTaskGroup { group in
        group.addTask { @MainActor [weak self] in
          for await _ in NotificationCenter.default.notifications(
            named: NSApplication.didChangeScreenParametersNotification
          ) {
            self?.handleScreenParametersChanged()
          }
        }

        group.addTask { @MainActor [weak self] in
          for await _ in NSWorkspace.shared.notificationCenter.notifications(
            named: NSWorkspace.activeSpaceDidChangeNotification
          ) {
            self?.handleActiveSpaceChanged()
          }
        }
      }
    }

    measurementView.delegate = self

    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  deinit {
    workspaceObservationTask?.cancel()
    screenCaptureTask?.cancel()
  }

  func move(to screen: NSScreen) {
    guard
      let displayID = screen.cgDirectDisplayID,
      self.displayID != displayID,
      let spaceID = screen.currentSpaceID
    else {
      return
    }

    self.displayID = displayID
    self.currentSpaceID = spaceID

    overlayWindow.setFrame(screen.frame, display: true)

    if case .span = measurementMode {
      captureScreenAndMeasureSpan()
    }
  }

  func setAppMode(_ appMode: AppMode) {
    guard self.appMode != appMode else {
      return
    }

    self.appMode = appMode
    self.overlayWindow.backgroundColor = appMode.overlayWindowBackgroundColor

    if appMode == .single {
      committedMeasurements.removeAll()
    }
  }

  private func handleScreenParametersChanged() {
    guard let screen = NSScreen.screen(for: displayID) else {
      if let newScreen = NSScreen.screenContainingMouse ?? .main {
        move(to: newScreen)
      } else {
        FileHandle.standardError.write(Data("Failed to determine screen after screen parameters changed.\n".utf8))
        NSApplication.shared.terminate(nil)
      }

      return
    }

    guard overlayWindow.frame != screen.frame else {
      return
    }

    overlayWindow.setFrame(screen.frame, display: true)

    if case .span = measurementMode {
      captureScreenAndMeasureSpan()
    }
  }

  private func handleActiveSpaceChanged() {
    guard
      let screen = NSScreen.screen(for: displayID),
      let spaceID = screen.currentSpaceID,
      currentSpaceID != spaceID
    else {
      return
    }

    self.currentSpaceID = spaceID

    NSApplication.shared.activate(ignoringOtherApps: true)

    if case .span = measurementMode {
      captureScreenAndMeasureSpan()
    }
  }

  private func handleMouseMoved(to location: CGPoint) {
    self.lastMouseLocation = location

    switch measurementMode {
    case .region: measureRegion()
    case .span: measureSpan()
    }
  }

  private func handleMouseDown(at location: CGPoint) {
    if let activeMeasurement {
      switch appMode {
      case .single:
        let result = activeMeasurement.formattedString

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)

        print(result)

        NSApplication.shared.terminate(nil)

      case .continuous:
        committedMeasurements.append(activeMeasurement)

        if case .region = measurementMode {
          self.activeMeasurement = nil
        }
      }
    } else if case .region = measurementMode {
      self.activeMeasurement = .region(RegionMeasurement(startLocation: location, endLocation: location))
    }
  }

  private func handleFlagsChanged(_ modifierFlags: NSEvent.ModifierFlags) {
    let hasCommand = modifierFlags.contains(.command)
    let hasShift = modifierFlags.contains(.shift)

    let nextMeasurementMode: MeasurementMode

    if hasCommand, hasShift {
      nextMeasurementMode = .span(.vertical)
    } else if hasCommand {
      nextMeasurementMode = .span(.horizontal)
    } else {
      nextMeasurementMode = .region
    }

    transition(to: nextMeasurementMode)
  }

  private func handleKeyPressed(_ keyCode: UInt16) {
    guard keyCode == 53 else {
      return
    }

    if case .region = measurementMode, activeMeasurement != nil {
      self.activeMeasurement = nil

    } else if appMode == .continuous, !committedMeasurements.isEmpty {
      committedMeasurements.removeLast()

    } else {
      NSApplication.shared.terminate(nil)
    }
  }

  private func measureRegion() {
    guard
      case .region(let regionMeasurement) = activeMeasurement,
      let mouseLocation,
      mouseLocation != regionMeasurement.endLocation
    else {
      return
    }

    self.activeMeasurement = .region(regionMeasurement.extended(to: mouseLocation))
  }

  private func captureScreenAndMeasureSpan() {
    self.screenCapture = nil
    self.activeMeasurement = nil

    screenCaptureTask?.cancel()
    self.screenCaptureTask = Task { [weak self, displayID] in
      do {
        let screenCapture = try await ScreenCaptureService.capture(displayID: displayID)

        guard let self, !Task.isCancelled else {
          return
        }

        self.screenCaptureTask = nil
        self.screenCapture = screenCapture

        measureSpan()
      } catch {
        FileHandle.standardError.write(Data(("Failed to capture screen: \(error.localizedDescription)\n").utf8))
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func measureSpan() {
    guard case .span(let axis) = measurementMode, let screenCapture, let mouseLocation else {
      return
    }

    let (startLocation, _, length) = EdgeDetector.detect(
      edgesIn: screenCapture,
      from: mouseLocation,
      alongAxis: axis,
      rgbDifferenceThreshold: Configuration.spanMeasurementRGBDifferenceThreshold
    )
    let spanMeasurement = SpanMeasurement(
      referenceLocation: mouseLocation,
      axis: axis,
      startLocation: startLocation,
      length: length
    )

    self.activeMeasurement = .span(spanMeasurement)
  }

  private func transition(to measurementMode: MeasurementMode) {
    guard self.measurementMode != measurementMode else {
      return
    }

    let previousMode = self.measurementMode

    self.measurementMode = measurementMode

    switch measurementMode {
    case .region:
      screenCaptureTask?.cancel()

      self.screenCaptureTask = nil
      self.screenCapture = nil

      if let lastRegionMeasurement, let mouseLocation {
        self.activeMeasurement = .region(lastRegionMeasurement.extended(to: mouseLocation))
      } else {
        self.activeMeasurement = nil
      }

      self.lastRegionMeasurement = nil

    case .span:
      if case .region(let regionMeasurement) = activeMeasurement {
        self.lastRegionMeasurement = regionMeasurement
      }

      if previousMode.isSpan {
        measureSpan()
      } else {
        captureScreenAndMeasureSpan()
      }
    }
  }

  private func updateMeasurementView() {
    measurementView.measurements = committedMeasurements + (activeMeasurement.map { [$0] } ?? [])
    measurementView.needsDisplay = true
  }
}

extension MeasurementSession: MeasurementViewDelegate {
  func measurementView(_ view: MeasurementView, didReceive action: MeasurementView.Event) {
    switch action {
    case .mouseMoved(let location): handleMouseMoved(to: location)
    case .mouseDown(let location): handleMouseDown(at: location)
    case .flagsChanged(let modifierFlags): handleFlagsChanged(modifierFlags)
    case .keyDown(let keyCode): handleKeyPressed(keyCode)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let appMode: AppMode
  private var measurementSession: MeasurementSession?

  init(appMode: AppMode) {
    self.appMode = appMode
    super.init()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    guard let screen = NSScreen.screenContainingMouse ?? .main else {
      FileHandle.standardError.write(Data("Failed to determine screen for measurement session.\n".utf8))
      exit(EXIT_FAILURE)
    }

    do {
      self.measurementSession = try MeasurementSession(screen: screen, appMode: appMode)
      observeIPCCommands()
    } catch {
      FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
      exit(EXIT_FAILURE)
    }
  }

  private func observeIPCCommands() {
    Task {
      let notificationCenter = DistributedNotificationCenter.default()

      for await notification in notificationCenter.notifications(named: IPCCommand.notificationName) {
        guard
          let userInfo = notification.userInfo,
          let ipcCommand = IPCCommand(userInfo: userInfo)
        else {
          continue
        }

        handleIPCCommand(ipcCommand)
      }
    }
  }

  private func handleIPCCommand(_ command: IPCCommand) {
    switch command {
    case .activate(let appMode):
      guard let screen = NSScreen.screenContainingMouse ?? .main else {
        return
      }

      measurementSession?.setAppMode(appMode)
      measurementSession?.move(to: screen)

      NSApplication.shared.activate(ignoringOtherApps: true)
    }
  }
}

enum IPCCommand {
  case activate(appMode: AppMode)

  static let notificationName = Notification.Name("\(Configuration.subsystem).IPCCommand")

  init?(userInfo: [AnyHashable: Any]) {
    guard let userInfo = userInfo as? [String: String] else {
      return nil
    }

    switch userInfo["command"] {
    case "activate":
      guard let appModeRawValue = userInfo["appMode"], let appMode = AppMode(rawValue: appModeRawValue) else {
        return nil
      }

      self = .activate(appMode: appMode)

    default:
      return nil
    }
  }

  func send() {
    var userInfo: [String: String] = [:]

    switch self {
    case .activate(let appMode):
      userInfo["command"] = "activate"
      userInfo["appMode"] = appMode.rawValue
    }

    DistributedNotificationCenter.default().postNotificationName(
      Self.notificationName,
      object: nil,
      userInfo: userInfo,
      deliverImmediately: true
    )
  }
}

let arguments = CommandLine.arguments.dropFirst()
let usageDescription = """
  Usage:
    \(ProcessInfo.processInfo.processName) [options]

  Options:
    -s, --single      Measure once, copy to clipboard, and exit (default)
    -c, --continuous  Measure continuously, keeping results on screen until cleared
    -h, --help        Show this help message
  """

guard arguments.count == 1 else {
  FileHandle.standardError.write(Data("Too many arguments.\n\n\(usageDescription)\n".utf8))
  exit(EX_USAGE)
}

var appMode: AppMode = .single

if let argument = arguments.first {
  switch argument {
  case "-s", "--single":
    appMode = .single

  case "-c", "--continuous":
    appMode = .continuous

  case "-h", "--help":
    print(usageDescription)
    exit(EXIT_SUCCESS)

  default:
    FileHandle.standardError.write(Data("Unknown argument: \(argument)\n\n\(usageDescription)\n".utf8))
    exit(EX_USAGE)
  }
}

guard let executablePath = CommandLine.arguments.first else {
  FileHandle.standardError.write(Data("Executable path not found in command line arguments.\n".utf8))
  exit(EXIT_FAILURE)
}

let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
let currentExecutableURL = URL(fileURLWithPath: executablePath).resolvingSymlinksInPath().standardizedFileURL
let existingInstance = NSWorkspace.shared.runningApplications.first { runningApplication in
  guard
    !runningApplication.isTerminated,
    runningApplication.processIdentifier != currentProcessIdentifier,
    let executableURL = runningApplication.executableURL?.resolvingSymlinksInPath().standardizedFileURL
  else {
    return false
  }

  return executableURL == currentExecutableURL
}

if existingInstance == nil {
  MainActor.assumeIsolated {
    let delegate = AppDelegate(appMode: appMode)
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
  }
} else {
  IPCCommand.activate(appMode: appMode).send()
  exit(EXIT_SUCCESS)
}
