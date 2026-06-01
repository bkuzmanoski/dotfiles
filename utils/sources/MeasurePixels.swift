import ScreenCaptureKit

enum Configuration {
  static let subsystem = "industries.britown.MeasurePixels"
  static let screenOverlayColor: NSColor = .black.withAlphaComponent(0.1)
  static let measurementLineColor: NSColor = .systemRed
  static let measurementAreaColor: NSColor = .systemRed.withAlphaComponent(0.15)
  static let spanMeasurementLineEndCapLength: CGFloat? = 3.0
  static let labelForegroundColor: NSColor = .white
  static let labelBackgroundColor: NSColor = .systemRed
  static let labelMargin: CGFloat = 6.0
  static let labelCornerRadius: CGFloat = 4.0
  static let labelPadding: (horizontal: CGFloat, vertical: CGFloat) = (4.0, 2.0)
  static let spanMeasurementRGBDifferenceThreshold = 20
}

struct FileOutputStream: TextOutputStream {
  static var standardError = FileOutputStream(fileHandle: .standardError)
  static var standardOutput = FileOutputStream(fileHandle: .standardOutput)

  private let fileHandle: FileHandle

  init(fileHandle: FileHandle) {
    self.fileHandle = fileHandle
  }

  mutating func write(_ string: String) {
    fileHandle.write(Data(string.utf8))
  }
}

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connectionID: CGSConnectionID, _ displayIdentifier: CFString?) -> Unmanaged<CFArray>?

typealias DisplayIdentifier = String
typealias SpaceID = UInt64

extension NSScreen {
  static var screenContainingMouse: NSScreen? {
    let mouseLocation = NSEvent.mouseLocation
    return screens.first { $0.frame.contains(mouseLocation) }
  }

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
    guard
      let displayIdentifier = self.displayIdentifier,
      let managedDisplaySpaces = CGSCopyManagedDisplaySpaces(
        CGSMainConnectionID(),
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

extension CGContext {
  func withBlendMode(_ blendMode: CGBlendMode, _ body: () -> Void) {
    saveGState()
    setBlendMode(blendMode)
    body()
    restoreGState()
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
    case .region(let measurement): return measurement.formattedString
    case .span(let measurement): return measurement.formattedString
    }
  }
}

struct RegionMeasurement: Equatable {
  let startLocation: CGPoint
  let endLocation: CGPoint

  var horizontalDirection: HorizontalDirection { endLocation.x >= startLocation.x ? .trailing : .leading }
  var verticalDirection: VerticalDirection { endLocation.y < startLocation.y ? .downward : .upward }

  var rect: CGRect {
    CGRect(
      x: startLocation.x,
      y: startLocation.y,
      width: endLocation.x - startLocation.x,
      height: endLocation.y - startLocation.y
    ).integral
  }

  var formattedString: String { "\(rect.width.compactString) × \(rect.height.compactString)" }

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

typealias BGRAPixel = UInt32

extension BGRAPixel {
  var blueComponent: UInt8 { UInt8(self & 0xff) }
  var greenComponent: UInt8 { UInt8((self >> 8) & 0xff) }
  var redComponent: UInt8 { UInt8((self >> 16) & 0xff) }
  var alphaComponent: UInt8 { UInt8((self >> 24) & 0xff) }
}

struct ScreenCapture {
  enum Error: Swift.Error, CustomStringConvertible {
    case unsupportedPixelFormat(
      byteOrder: CGImageByteOrderInfo,
      alphaInfo: CGImageAlphaInfo,
      bitsPerPixel: Int,
      bitsPerComponent: Int
    )
    case missingPixelData

    var description: String {
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
      image.byteOrderInfo == .order32Little,
      image.alphaInfo == .premultipliedFirst,
      image.bitsPerPixel == 32,
      image.bitsPerComponent == 8
    else {
      throw Error.unsupportedPixelFormat(
        byteOrder: image.byteOrderInfo,
        alphaInfo: image.alphaInfo,
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

  func withUnsafeBGRAPixelBuffer<Result>(_ body: (UnsafeBufferPointer<BGRAPixel>) throws -> Result) rethrows -> Result {
    let pixelCount = height * pixelsPerRow

    return try pixelDataPointer.withMemoryRebound(to: BGRAPixel.self, capacity: pixelCount) { pointer in
      let buffer = UnsafeBufferPointer(start: pointer, count: pixelCount)
      return try body(buffer)
    }
  }
}

extension UnsafeBufferPointer where Element == BGRAPixel {
  func hasRGBDifference(
    startingAt startIndex1: Int,
    and startIndex2: Int,
    length: Int,
    stride: Int,
    exceeding threshold: Int
  ) -> Bool {
    var offset1 = startIndex1
    var offset2 = startIndex2

    for _ in 0..<length {
      if rgbDifference(at: offset1, and: offset2) > threshold {
        return true
      }

      offset1 += stride
      offset2 += stride
    }

    return false
  }

  private func rgbDifference(at index1: Int, and index2: Int) -> Int {
    let pixel1 = self[index1]
    let pixel2 = self[index2]

    return
      abs(Int(pixel1.redComponent) - Int(pixel2.redComponent))
      + abs(Int(pixel1.greenComponent) - Int(pixel2.greenComponent))
      + abs(Int(pixel1.blueComponent) - Int(pixel2.blueComponent))
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

    return screenCapture.withUnsafeBGRAPixelBuffer { pixelBuffer in
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
          if pixelBuffer.hasRGBDifference(
            startingAt: rowStartBufferIndex + previousPixelX,
            and: rowStartBufferIndex + searchPixelX,
            length: pixelsPerPoint,
            stride: screenCapture.pixelsPerRow,
            exceeding: rgbDifferenceThreshold
          ) {
            break
          }

          previousPixelX = searchPixelX
          leadingPixelX = searchPixelX
        }

        previousPixelX = clampedPixelX

        var trailingPixelX = clampedPixelX

        for searchPixelX in stride(from: clampedPixelX + 1, to: screenCapture.width, by: 1) {
          if pixelBuffer.hasRGBDifference(
            startingAt: rowStartBufferIndex + previousPixelX,
            and: rowStartBufferIndex + searchPixelX,
            length: pixelsPerPoint,
            stride: screenCapture.pixelsPerRow,
            exceeding: rgbDifferenceThreshold
          ) {
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
          if pixelBuffer.hasRGBDifference(
            startingAt: previousPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            and: searchPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            length: pixelsPerPoint,
            stride: 1,
            exceeding: rgbDifferenceThreshold
          ) {
            break
          }

          previousPixelY = searchPixelY
          topPixelY = searchPixelY
        }

        previousPixelY = clampedPixelY

        var bottomPixelY = clampedPixelY

        for searchPixelY in stride(from: clampedPixelY + 1, to: screenCapture.height, by: 1) {
          if pixelBuffer.hasRGBDifference(
            startingAt: previousPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            and: searchPixelY * screenCapture.pixelsPerRow + columnStartBufferIndex,
            length: pixelsPerPoint,
            stride: 1,
            exceeding: rgbDifferenceThreshold
          ) {
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
  enum Error: Swift.Error, CustomStringConvertible {
    case screenNotFound(CGDirectDisplayID)
    case displayNotFound
    case missingSdrImage

    var description: String {
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
      excludingApplications: availableContent.applications
        .first { $0.processID == NSRunningApplication.current.processIdentifier }
        .map { [$0] }
        ?? [],
      exceptingWindows: []
    )
    let configuration = SCScreenshotConfiguration()
    configuration.dynamicRange = .sdr
    configuration.ignoreShadows = false
    configuration.showsCursor = false

    let screenshot: SCScreenshotOutput = try await SCScreenshotManager.captureScreenshot(
      contentFilter: contentFilter,
      configuration: configuration
    )

    guard let image = screenshot.sdrImage else {
      throw Error.missingSdrImage
    }

    return try ScreenCapture(image: image, displayID: displayID, scaleFactor: screen.backingScaleFactor)
  }
}

final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

@MainActor
protocol MeasurementViewDelegate: AnyObject {
  func measurementView(_ view: MeasurementView, didMoveMouseTo locationInWindow: CGPoint)
  func measurementView(_ view: MeasurementView, didClickAt locationInWindow: CGPoint)
  func measurementView(_ view: MeasurementView, didChangeModifierFlags flags: NSEvent.ModifierFlags)
  func measurementViewDidCancel(_ view: MeasurementView)
  func measurementViewDidRequestUndo(_ view: MeasurementView)
  func measurementViewDidRequestRedo(_ view: MeasurementView)
}

@MainActor
final class MeasurementView: NSView {
  private struct Label {
    enum Position {
      case leading
      case trailing
      case top
      case bottom
    }

    let attributedString: NSAttributedString

    private let size: CGSize
    private let anchor: CGPoint
    private let preferredPosition: Position
    private let margin: CGFloat

    init(
      text: String,
      anchor: CGPoint,
      preferredPosition: Position,
      margin: CGFloat,
      padding: (horizontal: CGFloat, vertical: CGFloat),
      attributes: [NSAttributedString.Key: Any]
    ) {
      let attributedString = NSAttributedString(string: text, attributes: attributes)
      let textSize = attributedString.size()

      self.attributedString = attributedString
      self.size = CGSize(
        width: ceil(textSize.width) + padding.horizontal * 2,
        height: ceil(textSize.height) + padding.vertical * 2
      )
      self.anchor = anchor
      self.preferredPosition = preferredPosition
      self.margin = margin
    }

    func rect(within bounds: CGRect) -> CGRect {
      var originX: CGFloat
      var originY: CGFloat

      switch preferredPosition {
      case .leading:
        originX = anchor.x - size.width - margin

        if originX < bounds.minX {
          originX = anchor.x + margin
        }

        originY = anchor.y - size.height / 2

      case .trailing:
        originX = anchor.x + margin

        if originX + size.width > bounds.maxX {
          originX = anchor.x - size.width - margin
        }

        originY = anchor.y - size.height / 2

      case .top:
        originX = anchor.x - size.width / 2
        originY = anchor.y + margin

        if originY + size.height > bounds.maxY {
          originY = anchor.y - size.height - margin
        }

      case .bottom:
        originX = anchor.x - size.width / 2
        originY = anchor.y - size.height - margin

        if originY < bounds.minY {
          originY = anchor.y + margin
        }
      }

      return CGRect(
        x: max(bounds.minX + margin, min(originX, bounds.maxX - size.width - margin)),
        y: max(bounds.minY + margin, min(originY, bounds.maxY - size.height - margin)),
        width: size.width,
        height: size.height
      )
    }
  }

  weak var delegate: MeasurementViewDelegate?

  var measurements: [Measurement] = [] {
    didSet {
      self.needsDisplay = true
    }
  }

  override var acceptsFirstResponder: Bool { true }

  private let style: MeasurementStyle
  private var trackingArea: NSTrackingArea?

  init(style: MeasurementStyle, frame frameRect: CGRect = .zero) {
    self.style = style
    super.init(frame: frameRect)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    return true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let trackingArea {
      removeTrackingArea(trackingArea)
    }

    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
      owner: self,
      userInfo: nil
    )

    addTrackingArea(trackingArea)

    self.trackingArea = trackingArea
  }

  override func resetCursorRects() {
    super.resetCursorRects()

    if let cursor = NSCursor.screenshotSelection {
      addCursorRect(bounds, cursor: cursor)
    }
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.screenshotSelection?.set()
  }

  override func mouseMoved(with event: NSEvent) {
    delegate?.measurementView(self, didMoveMouseTo: event.locationInWindow)
  }

  override func mouseDown(with event: NSEvent) {
    delegate?.measurementView(self, didClickAt: event.locationInWindow)
  }

  override func flagsChanged(with event: NSEvent) {
    delegate?.measurementView(self, didChangeModifierFlags: event.modifierFlags)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

    if modifierFlags.contains(.command) {
      switch event.charactersIgnoringModifiers?.lowercased() {
      case "q":
        NSApplication.shared.terminate(nil)
        return true

      case "z":
        if modifierFlags.contains(.shift) {
          delegate?.measurementViewDidRequestRedo(self)
        } else {
          delegate?.measurementViewDidRequestUndo(self)
        }

        return true

      default:
        break
      }
    }

    return super.performKeyEquivalent(with: event)
  }

  override func cancelOperation(_ sender: Any?) {
    delegate?.measurementViewDidCancel(self)
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    for measurement in measurements {
      switch measurement {
      case .region(let measurement): drawRegionMeasurement(measurement, in: context)
      case .span(let measurement): drawSpanMeasurement(measurement, in: context)
      }
    }
  }

  private func drawRegionMeasurement(_ measurement: RegionMeasurement, in context: CGContext) {
    let measurementRect = measurement.rect
    let insetMeasurementRect = measurementRect.insetBy(dx: 0.5, dy: 0.5)
    let cornerPoint = NSPoint(
      x: measurement.horizontalDirection == .trailing ? insetMeasurementRect.minX : insetMeasurementRect.maxX,
      y: measurement.verticalDirection == .downward ? insetMeasurementRect.maxY : insetMeasurementRect.minY
    )
    let horizontalLineEndPoint = NSPoint(
      x: measurement.horizontalDirection == .trailing ? measurementRect.maxX : measurementRect.minX,
      y: cornerPoint.y
    )
    let verticalLineEndPoint = NSPoint(
      x: cornerPoint.x,
      y: measurement.verticalDirection == .downward ? measurementRect.minY : measurementRect.maxY
    )
    let horizontalLineMaskEndPoint = NSPoint(
      x: horizontalLineEndPoint.x + (measurement.horizontalDirection == .trailing ? -0.5 : 0.5),
      y: horizontalLineEndPoint.y
    )
    let verticalLineMaskEndPoint = NSPoint(
      x: verticalLineEndPoint.x,
      y: verticalLineEndPoint.y + (measurement.verticalDirection == .downward ? 0.5 : -0.5)
    )

    let maskPath = NSBezierPath()

    style.measurementAreaColor.setFill()
    measurementRect.fill()

    maskPath.move(to: verticalLineMaskEndPoint)
    maskPath.line(to: cornerPoint)
    maskPath.line(to: horizontalLineMaskEndPoint)

    context.withBlendMode(.destinationOut) {
      NSColor.black.setStroke()
      maskPath.lineWidth = 3.0
      maskPath.lineCapStyle = .square
      maskPath.lineJoinStyle = .miter
      maskPath.stroke()
    }

    let linePath = NSBezierPath()
    linePath.move(to: horizontalLineEndPoint)
    linePath.line(to: cornerPoint)
    linePath.line(to: verticalLineEndPoint)

    style.measurementLineColor.setStroke()
    linePath.lineWidth = 1.0
    linePath.stroke()

    drawLabel(
      Label(
        text: measurementRect.width.compactString,
        anchor: CGPoint(x: insetMeasurementRect.midX, y: cornerPoint.y),
        preferredPosition: measurement.verticalDirection == .downward ? .top : .bottom,
        margin: style.labelMargin,
        padding: style.labelPadding,
        attributes: style.labelAttributes
      ),
      in: context
    )
    drawLabel(
      Label(
        text: measurementRect.height.compactString,
        anchor: CGPoint(x: cornerPoint.x, y: insetMeasurementRect.midY),
        preferredPosition: measurement.horizontalDirection == .trailing ? .leading : .trailing,
        margin: style.labelMargin,
        padding: style.labelPadding,
        attributes: style.labelAttributes
      ),
      in: context
    )
  }

  private func drawSpanMeasurement(_ measurement: SpanMeasurement, in context: CGContext) {
    let startPoint = NSPoint(
      x: measurement.axis == .vertical ? measurement.startLocation.x + 0.5 : measurement.startLocation.x,
      y: measurement.axis == .horizontal ? measurement.startLocation.y + 0.5 : measurement.startLocation.y
    )
    let endPoint = NSPoint(
      x: measurement.axis == .vertical ? measurement.endLocation.x + 0.5 : measurement.endLocation.x,
      y: measurement.axis == .horizontal ? measurement.endLocation.y + 0.5 : measurement.endLocation.y
    )
    let maskStartPoint = NSPoint(
      x: startPoint.x + (measurement.axis == .horizontal ? 0.5 : 0.0),
      y: startPoint.y + (measurement.axis == .vertical ? 0.5 : 0.0)
    )
    let maskEndPoint = NSPoint(
      x: endPoint.x + (measurement.axis == .horizontal ? -0.5 : 0.0),
      y: endPoint.y + (measurement.axis == .vertical ? -0.5 : 0.0)
    )

    let maskPath = NSBezierPath()
    maskPath.move(to: maskStartPoint)
    maskPath.line(to: maskEndPoint)

    let linePath = NSBezierPath()
    linePath.move(to: startPoint)
    linePath.line(to: endPoint)

    if let endCapLength = style.spanMeasurementLineEndCapLength, measurement.length > endCapLength * 2 {
      switch measurement.axis {
      case .horizontal:
        let leadingEndCapX = startPoint.x + 0.5
        let trailingEndCapX = endPoint.x - 0.5
        let endCapMinY = startPoint.y - endCapLength
        let endCapMaxY = startPoint.y + endCapLength
        let maskEndCapMinY = endCapMinY + 0.5
        let maskEndCapMaxY = endCapMaxY - 0.5

        maskPath.move(to: NSPoint(x: leadingEndCapX, y: maskEndCapMinY))
        maskPath.line(to: NSPoint(x: leadingEndCapX, y: maskEndCapMaxY))
        maskPath.move(to: NSPoint(x: trailingEndCapX, y: maskEndCapMinY))
        maskPath.line(to: NSPoint(x: trailingEndCapX, y: maskEndCapMaxY))

        linePath.move(to: NSPoint(x: leadingEndCapX, y: endCapMinY))
        linePath.line(to: NSPoint(x: leadingEndCapX, y: endCapMaxY))
        linePath.move(to: NSPoint(x: trailingEndCapX, y: endCapMinY))
        linePath.line(to: NSPoint(x: trailingEndCapX, y: endCapMaxY))

      case .vertical:
        let topEndCapY = endPoint.y - 0.5
        let bottomEndCapY = startPoint.y + 0.5
        let endCapMinX = startPoint.x - endCapLength
        let endCapMaxX = startPoint.x + endCapLength
        let maskEndCapMinX = endCapMinX + 0.5
        let maskEndCapMaxX = endCapMaxX - 0.5

        maskPath.move(to: NSPoint(x: maskEndCapMinX, y: bottomEndCapY))
        maskPath.line(to: NSPoint(x: maskEndCapMaxX, y: bottomEndCapY))
        maskPath.move(to: NSPoint(x: maskEndCapMinX, y: topEndCapY))
        maskPath.line(to: NSPoint(x: maskEndCapMaxX, y: topEndCapY))

        linePath.move(to: NSPoint(x: endCapMinX, y: bottomEndCapY))
        linePath.line(to: NSPoint(x: endCapMaxX, y: bottomEndCapY))
        linePath.move(to: NSPoint(x: endCapMinX, y: topEndCapY))
        linePath.line(to: NSPoint(x: endCapMaxX, y: topEndCapY))
      }
    }

    context.withBlendMode(.destinationOut) {
      NSColor.black.setStroke()
      maskPath.lineWidth = 3.0
      maskPath.lineCapStyle = .square
      maskPath.stroke()
    }

    style.measurementLineColor.setStroke()
    linePath.lineWidth = 1.0
    linePath.stroke()

    drawLabel(
      Label(
        text: measurement.length.compactString,
        anchor: CGPoint(x: floor((startPoint.x + endPoint.x) / 2), y: floor((startPoint.y + endPoint.y) / 2)),
        preferredPosition: measurement.axis == .horizontal ? .bottom : .trailing,
        margin: style.labelMargin,
        padding: style.labelPadding,
        attributes: style.labelAttributes
      ),
      in: context
    )
  }

  private func drawLabel(_ label: Label, in context: CGContext) {
    let labelRect = label.rect(within: self.frame)
    let maskPath = NSBezierPath(
      roundedRect: labelRect.insetBy(dx: -1.0, dy: -1.0),
      xRadius: style.labelCornerRadius > 0 ? style.labelCornerRadius + 1.0 : 0.0,
      yRadius: style.labelCornerRadius > 0 ? style.labelCornerRadius + 1.0 : 0.0
    )

    context.withBlendMode(.destinationOut) {
      NSColor.black.set()
      maskPath.fill()
    }

    let backgroundPath = NSBezierPath(
      roundedRect: labelRect,
      xRadius: style.labelCornerRadius,
      yRadius: style.labelCornerRadius
    )

    style.labelBackgroundColor.setFill()
    backgroundPath.fill()

    label.attributedString.draw(
      at: CGPoint(
        x: labelRect.minX + style.labelPadding.horizontal,
        y: labelRect.minY + style.labelPadding.vertical
      )
    )
  }
}

enum AppMode: String {
  case single
  case continuous
}

struct MeasurementStyle {
  let measurementLineColor: NSColor
  let measurementAreaColor: NSColor
  let spanMeasurementLineEndCapLength: CGFloat?
  let labelForegroundColor: NSColor
  let labelBackgroundColor: NSColor
  let labelMargin: CGFloat
  let labelCornerRadius: CGFloat
  let labelPadding: (horizontal: CGFloat, vertical: CGFloat)
  let labelAttributes: [NSAttributedString.Key: Any]

  private let screenOverlayColor: NSColor

  init(
    screenOverlayColor: NSColor = NSColor.black.withAlphaComponent(0.2),
    measurementLineColor: NSColor = .white,
    measurementAreaColor: NSColor = NSColor.white.withAlphaComponent(0.3),
    spanMeasurementLineEndCapLength: CGFloat? = nil,
    labelForegroundColor: NSColor = .white,
    labelBackgroundColor: NSColor = NSColor.black.withAlphaComponent(0.7),
    labelMargin: CGFloat = 4.0,
    labelCornerRadius: CGFloat = 4.0,
    labelPadding: (horizontal: CGFloat, vertical: CGFloat) = (6.0, 2.0),
    labelAttributes: [NSAttributedString.Key: Any]
  ) {
    self.screenOverlayColor = screenOverlayColor
    self.measurementLineColor = measurementLineColor
    self.measurementAreaColor = measurementAreaColor
    self.spanMeasurementLineEndCapLength = spanMeasurementLineEndCapLength
    self.labelForegroundColor = labelForegroundColor
    self.labelBackgroundColor = labelBackgroundColor
    self.labelMargin = labelMargin
    self.labelCornerRadius = labelCornerRadius
    self.labelPadding = labelPadding
    self.labelAttributes = labelAttributes
  }

  func screenOverlayColor(for appMode: AppMode) -> NSColor {
    return appMode == .single ? screenOverlayColor : .clear
  }
}

@MainActor
final class MeasurementSession {
  enum Error: Swift.Error, CustomStringConvertible {
    case accessibilityPermissionNotGranted
    case screenCapturePermissionNotGranted
    case failedToDetermineDisplayID
    case failedToDetermineSpaceID
    case failedToCreateEventTap
    case failedToCreateRunLoopSource

    var description: String {
      switch self {
      case .accessibilityPermissionNotGranted: "Accessibility permission not granted."
      case .screenCapturePermissionNotGranted: "Screen capture permission not granted."
      case .failedToDetermineDisplayID: "Failed to determine display ID for the specified screen."
      case .failedToDetermineSpaceID: "Failed to determine current space ID for the specified screen."
      case .failedToCreateEventTap: "Failed to create event tap."
      case .failedToCreateRunLoopSource: "Failed to create run loop source for event tap."
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

  private let style: MeasurementStyle
  private let spanMeasurementRGBDifferenceThreshold: Int
  private let measurementView: MeasurementView
  private let overlayWindow: OverlayWindow
  private var appMode: AppMode
  private var displayID: CGDirectDisplayID
  private var currentSpaceID: SpaceID
  private var eventTap: CFMachPort?
  private var runLoopSource: CFRunLoopSource?
  private var workspaceObservationTask: Task<Void, Never>?
  private var screenCaptureTask: Task<Void, Never>?
  private var screenCapture: ScreenCapture?
  private var measurementMode: MeasurementMode = .region
  private var isPassthroughModeEnabled: Bool = false
  private var lastMouseLocation: CGPoint?
  private var lastRegionMeasurement: RegionMeasurement?

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

  private var undoneMeasurements: [Measurement] = []

  private var mouseLocation: CGPoint? {
    lastMouseLocation
      ?? (NSScreen.screen(for: displayID)?.frame.contains(NSEvent.mouseLocation) ?? false
        ? NSEvent.mouseLocation
        : nil)
  }

  init(
    appMode: AppMode,
    screen: NSScreen,
    style: MeasurementStyle,
    spanMeasurementRGBDifferenceThreshold: Int
  ) throws {
    guard AXIsProcessTrustedWithOptions(nil) else {
      throw Error.accessibilityPermissionNotGranted
    }

    guard CGPreflightScreenCaptureAccess() else {
      throw Error.screenCapturePermissionNotGranted
    }

    guard let displayID = screen.cgDirectDisplayID else {
      throw Error.failedToDetermineDisplayID
    }

    guard let currentSpaceID = screen.currentSpaceID else {
      throw Error.failedToDetermineSpaceID
    }

    let measurementView = MeasurementView(style: style)
    let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.collectionBehavior = [.ignoresCycle, .stationary, .auxiliary, .canJoinAllSpaces]
    window.level = .screenSaver
    window.backgroundColor = style.screenOverlayColor(for: appMode)
    window.contentView = measurementView
    window.ignoresMouseEvents = false

    self.style = style
    self.spanMeasurementRGBDifferenceThreshold = spanMeasurementRGBDifferenceThreshold
    self.measurementView = measurementView
    self.overlayWindow = window
    self.appMode = appMode
    self.displayID = displayID
    self.currentSpaceID = currentSpaceID

    guard
      let eventTap = CGEvent.tapCreate(
        tap: .cghidEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: 1 << CGEventType.flagsChanged.rawValue,
        callback: { _, _, event, refcon in
          guard let refcon else {
            return Unmanaged.passUnretained(event)
          }

          return
            Unmanaged<MeasurementSession>.fromOpaque(refcon).takeUnretainedValue().handleEvent(event)
            ? nil
            : Unmanaged.passUnretained(event)
        },
        userInfo: Unmanaged.passUnretained(self).toOpaque()
      )
    else {
      throw Error.failedToCreateEventTap
    }

    guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
      CFMachPortInvalidate(eventTap)
      throw Error.failedToCreateRunLoopSource
    }

    CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: eventTap, enable: true)

    let workspaceObservationTask = Task {
      await withDiscardingTaskGroup { [weak self] group in
        group.addTask {
          for await _ in NotificationCenter.default.notifications(
            named: NSApplication.didChangeScreenParametersNotification
          ) {
            await self?.handleScreenParametersChanged()
          }
        }

        for notificationName in [
          NSWorkspace.activeSpaceDidChangeNotification,
          NSWorkspace.didLaunchApplicationNotification,
          NSWorkspace.didActivateApplicationNotification
        ] {
          group.addTask {
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: notificationName) {
              await MainActor.run {
                guard let self else {
                  return
                }

                if notificationName == NSWorkspace.activeSpaceDidChangeNotification {
                  self.reactivateAppIfNeeded()
                  self.handleSpaceChanged()
                } else {
                  self.reactivateAppIfNeeded(withDelay: true)
                }
              }
            }
          }
        }
      }
    }

    self.eventTap = eventTap
    self.runLoopSource = runLoopSource
    self.workspaceObservationTask = workspaceObservationTask

    measurementView.delegate = self
    window.makeKeyAndOrderFront(nil)

    reactivateAppIfNeeded()
  }

  isolated deinit {
    overlayWindow.close()

    if let eventTap, let runLoopSource {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
      CFMachPortInvalidate(eventTap)
    }

    workspaceObservationTask?.cancel()
    screenCaptureTask?.cancel()
  }

  func setAppMode(_ appMode: AppMode) {
    guard self.appMode != appMode else {
      return
    }

    self.appMode = appMode
    self.overlayWindow.backgroundColor = style.screenOverlayColor(for: appMode)

    if appMode == .single {
      self.committedMeasurements.removeAll()
      self.undoneMeasurements.removeAll()
    }
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
    reactivateAppIfNeeded()

    if case .span = measurementMode {
      captureScreenAndMeasureSpan()
    }
  }

  private func handleEvent(_ event: CGEvent) -> Bool {
    guard event.type != .tapDisabledByTimeout, event.type != .tapDisabledByUserInput else {
      if let eventTap {
        CGEvent.tapEnable(tap: eventTap, enable: true)
      }

      return false
    }

    if event.flags.contains(.maskSecondaryFn) {
      self.isPassthroughModeEnabled = true

      NSApplication.shared.hide(nil)

      return true

    } else if isPassthroughModeEnabled {
      self.isPassthroughModeEnabled = false

      reactivateAppIfNeeded()
      handleMouseMoved(to: NSEvent.mouseLocation)

      return true

    } else {
      return false
    }
  }

  private func handleScreenParametersChanged() {
    guard let screen = NSScreen.screen(for: displayID) else {
      if let newScreen = NSScreen.screenContainingMouse ?? .main {
        move(to: newScreen)
      } else {
        print("Failed to determine screen after screen parameters changed.", to: &FileOutputStream.standardError)
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

  private func handleSpaceChanged() {
    guard
      let screen = NSScreen.screen(for: displayID),
      let spaceID = screen.currentSpaceID,
      currentSpaceID != spaceID
    else {
      return
    }

    self.currentSpaceID = spaceID

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
        guard !committedMeasurements.contains(activeMeasurement) else {
          return
        }

        self.committedMeasurements.append(activeMeasurement)
        self.undoneMeasurements.removeAll()

        if case .region = measurementMode {
          self.activeMeasurement = nil
        }
      }
    } else if case .region = measurementMode {
      self.activeMeasurement = .region(RegionMeasurement(startLocation: location, endLocation: location))
    }
  }

  private func handleFlagsChanged(_ modifierFlags: NSEvent.ModifierFlags) {
    let isOptionKeyPressed = modifierFlags.contains(.option)
    let isShiftKeyPressed = modifierFlags.contains(.shift)

    let nextMeasurementMode: MeasurementMode

    if isOptionKeyPressed, isShiftKeyPressed {
      nextMeasurementMode = .span(.vertical)
    } else if isOptionKeyPressed {
      nextMeasurementMode = .span(.horizontal)
    } else {
      nextMeasurementMode = .region
    }

    transition(to: nextMeasurementMode)
  }

  private func handleCancel() {
    if case .region = measurementMode, activeMeasurement != nil {
      self.activeMeasurement = nil
    } else {
      NSApplication.shared.terminate(nil)
    }
  }

  private func handleUndo() {
    guard appMode == .continuous, !committedMeasurements.isEmpty else {
      return
    }

    let undoneMeasurement = committedMeasurements.removeLast()

    self.undoneMeasurements.append(undoneMeasurement)
  }

  private func handleRedo() {
    guard appMode == .continuous, !undoneMeasurements.isEmpty else {
      return
    }

    let redoneMeasurement = undoneMeasurements.removeLast()

    self.committedMeasurements.append(redoneMeasurement)
  }

  private func measureRegion() {
    guard
      case .region(let measurement) = activeMeasurement,
      let mouseLocation,
      mouseLocation != measurement.endLocation
    else {
      return
    }

    self.activeMeasurement = .region(measurement.extended(to: mouseLocation))
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
        print("Failed to capture screen: \(error)", to: &FileOutputStream.standardError)
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
      rgbDifferenceThreshold: spanMeasurementRGBDifferenceThreshold
    )
    let measurement = SpanMeasurement(
      referenceLocation: mouseLocation,
      axis: axis,
      startLocation: startLocation,
      length: length
    )

    self.activeMeasurement = .span(measurement)
  }

  private func reactivateAppIfNeeded(withDelay delay: Bool = false) {
    guard !isPassthroughModeEnabled, overlayWindow.frame.contains(NSEvent.mouseLocation) else {
      return
    }

    Task { [weak self] in
      if delay {
        try? await Task.sleep(for: .milliseconds(300))
      }

      guard let self else {
        return
      }

      NSApplication.shared.activate(ignoringOtherApps: true)
      overlayWindow.invalidateCursorRects(for: measurementView)
    }
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
      if case .region(let measurement) = activeMeasurement {
        self.lastRegionMeasurement = measurement
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
  }
}

extension MeasurementSession: MeasurementViewDelegate {
  func measurementView(_ view: MeasurementView, didMoveMouseTo locationInWindow: CGPoint) {
    handleMouseMoved(to: locationInWindow)
  }

  func measurementView(_ view: MeasurementView, didClickAt locationInWindow: CGPoint) {
    handleMouseDown(at: locationInWindow)
  }

  func measurementView(_ view: MeasurementView, didChangeModifierFlags flags: NSEvent.ModifierFlags) {
    handleFlagsChanged(flags)
  }

  func measurementViewDidCancel(_ view: MeasurementView) {
    handleCancel()
  }

  func measurementViewDidRequestUndo(_ view: MeasurementView) {
    handleUndo()
  }

  func measurementViewDidRequestRedo(_ view: MeasurementView) {
    handleRedo()
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
      print("Failed to determine screen for measurement session.", to: &FileOutputStream.standardError)
      exit(EXIT_FAILURE)
    }

    do {
      self.measurementSession = try MeasurementSession(
        appMode: appMode,
        screen: screen,
        style: MeasurementStyle(
          screenOverlayColor: Configuration.screenOverlayColor,
          measurementLineColor: Configuration.measurementLineColor,
          measurementAreaColor: Configuration.measurementAreaColor,
          spanMeasurementLineEndCapLength: Configuration.spanMeasurementLineEndCapLength,
          labelForegroundColor: Configuration.labelForegroundColor,
          labelBackgroundColor: Configuration.labelBackgroundColor,
          labelMargin: Configuration.labelMargin,
          labelCornerRadius: Configuration.labelCornerRadius,
          labelPadding: Configuration.labelPadding,
          labelAttributes: [
            .font: NSFont.systemFont(ofSize: NSFont.labelFontSize, weight: .regular),
            .foregroundColor: Configuration.labelForegroundColor
          ]
        ),
        spanMeasurementRGBDifferenceThreshold: Configuration.spanMeasurementRGBDifferenceThreshold
      )
      observeIPCCommands()
    } catch {
      print(error, to: &FileOutputStream.standardError)
      exit(EXIT_FAILURE)
    }
  }

  private func observeIPCCommands() {
    Task {
      for await notification
        in DistributedNotificationCenter
        .default()
        .notifications(named: IPCCommand.notificationName)
      {
        guard let command = IPCCommand(userInfo: notification.userInfo) else {
          continue
        }

        handleIPCCommand(command)
      }
    }
  }

  private func handleIPCCommand(_ command: IPCCommand) {
    switch command {
    case .activate(let appMode):
      guard let screen = NSScreen.screenContainingMouse ?? .main else {
        print("Failed to determine screen for measurement session.", to: &FileOutputStream.standardError)
        NSApplication.shared.terminate(nil)

        return
      }

      measurementSession?.setAppMode(appMode)
      measurementSession?.move(to: screen)
    }
  }
}

enum IPCCommand {
  case activate(appMode: AppMode)

  static let notificationName = Notification.Name("\(Configuration.subsystem).IPCCommand")

  init?(userInfo: [AnyHashable: Any]?) {
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

guard arguments.count <= 1 else {
  print("Too many arguments.\n\n\(usageDescription)", to: &FileOutputStream.standardError)
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
    print("Unknown argument: \(argument)\n\n\(usageDescription)", to: &FileOutputStream.standardError)
    exit(EX_USAGE)
  }
}

guard let executablePath = CommandLine.arguments.first else {
  print("Executable path not found in command line arguments.", to: &FileOutputStream.standardError)
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
