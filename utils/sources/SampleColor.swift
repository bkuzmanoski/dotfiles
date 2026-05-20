import ScreenCaptureKit

enum Configuration {
  // TODO...
  static let subsystem = "industries.britown.SampleColor"
  static let loupeCornerRadius: CGFloat = 20.0
  static let gridSize = 15
  static let magnification: CGFloat = 10.0
  static let gridLineColor: NSColor = .labelColor.withAlphaComponent(0.15)
  static let borderColor: NSColor = .windowBackgroundColor
  static let shadowBorderColor: NSColor = .shadowColor.withAlphaComponent(0.3)
  static let reticleOuterColor: NSColor = .labelColor
  static let reticleInnerColor: NSColor = .windowBackgroundColor
  static let labelMargin: CGFloat = 12.0
  static let labelHorizontalPadding: CGFloat = 10.0
  static let labelVerticalPadding: CGFloat = 7.0
  static let labelLineSpacing: CGFloat = 3.0
  static let labelCornerRadius: CGFloat = 14.0
  static let labelBackgroundColor: NSColor = .windowBackgroundColor.withAlphaComponent(0.88)
  static let valueFontSize: CGFloat = 12.0
  static let valueForegroundColor: NSColor = .labelColor
  static let detailFontSize: CGFloat = 10.0
  static let detailForegroundColor: NSColor = .secondaryLabelColor
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

extension CGColorSpace {
  var displayName: String { NSColorSpace(cgColorSpace: self)?.localizedName ?? "Unknown" }
}

extension String.StringInterpolation {
  mutating func appendInterpolation(hex value: Int, padTo length: Int = 2) {
    let clampedValue = max(0, min(255, value))
    let hexString = String(clampedValue, radix: 16, uppercase: false)
    let padding = String(repeating: "0", count: max(0, length - hexString.count))

    appendLiteral(padding + hexString)
  }
}

enum OutputFormat {
  case hex
  case rgb
}

enum OutputColorSpace {
  case sRGB
  case native
}

struct ColorSamplerOptions {
  static let `default` = ColorSamplerOptions(outputFormat: .hex, colorSpace: .sRGB, useSystemSampler: false)

  let outputFormat: OutputFormat
  let colorSpace: OutputColorSpace
  let useSystemSampler: Bool
}

struct ColorSample {
  let red: UInt8
  let green: UInt8
  let blue: UInt8

  init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  init(pixel: UInt32) {
    self.red = UInt8((pixel >> 16) & 0xFF)
    self.green = UInt8((pixel >> 8) & 0xFF)
    self.blue = UInt8(pixel & 0xFF)
  }

  func formattedString(for outputFormat: OutputFormat) -> String {
    switch outputFormat {
    case .hex: return "#\(hex: Int(red))\(hex: Int(green))\(hex: Int(blue))"
    case .rgb: return "rgb(\(red), \(green), \(blue))"
    }
  }
}

struct SampleGrid {
  enum Error: Swift.Error, LocalizedError {
    case pixelCountMismatch(expected: Int, actual: Int)
    case unableToAcceessPixelData
    case failedToCreateCGImage

    var errorDescription: String? {
      switch self {
      case .pixelCountMismatch(let expected, let actual): "Pixel count mismatch: expected \(expected), got \(actual)."
      case .unableToAcceessPixelData: "Unable to access pixel data."
      case .failedToCreateCGImage: "Failed to create CGImage from pixel data."
      }
    }
  }

  let size: Int
  let colorSpace: CGColorSpace
  let pixels: [UInt32]
  let loupeImage: CGImage

  var centerSample: ColorSample? {
    pixels.indices.contains(size * size / 2) ? ColorSample(pixel: pixels[size * size / 2]) : nil
  }

  init(size: Int, colorSpace: CGColorSpace, pixels: [UInt32]) throws {
    self.size = size
    self.colorSpace = colorSpace
    self.pixels = pixels
    self.loupeImage = try Self.makeLoupeImage(from: pixels, size: size, colorSpace: colorSpace)
  }

  private static func makeLoupeImage(from pixels: [UInt32], size: Int, colorSpace: CGColorSpace) throws -> CGImage {
    guard pixels.count == size * size else {
      throw Error.pixelCountMismatch(expected: size * size, actual: pixels.count)
    }

    let pixelData = pixels.withUnsafeBufferPointer { pixelBuffer in
      Data(buffer: pixelBuffer)
    }

    guard let provider = CGDataProvider(data: pixelData as CFData) else {
      throw Error.unableToAcceessPixelData
    }

    let cgImage = CGImage(
      width: size,
      height: size,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: size * MemoryLayout<UInt32>.stride,
      space: colorSpace,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue).union(.byteOrder32Little),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )

    guard let cgImage else {
      throw Error.failedToCreateCGImage
    }

    return cgImage
  }
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

  let width: Int
  let height: Int
  let scaleFactor: CGFloat
  let pixelsPerRow: Int
  let sourceColorSpace: CGColorSpace

  private let pixelData: CFData
  private let pixelDataPointer: UnsafePointer<UInt8>

  init(image: CGImage, scaleFactor: CGFloat) throws {
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

    self.width = image.width
    self.height = image.height
    self.scaleFactor = scaleFactor
    self.sourceColorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
    self.pixelsPerRow = image.bytesPerRow / (image.bitsPerPixel / 8)
    self.pixelData = pixelData
    self.pixelDataPointer = pixelDataPointer
  }

  func sampleGrid(at location: CGPoint, size: Int) throws -> SampleGrid {
    let halfSize = size / 2
    let targetPixelX = Int(floor(location.x * scaleFactor))
    let targetPixelY = Int(CGFloat(height) - floor(location.y * scaleFactor) - 1)
    let clampedTargetPixelX = max(0, min(targetPixelX, width - 1))
    let clampedTargetPixelY = max(0, min(targetPixelY, height - 1))

    var sampledPixels = [UInt32]()
    sampledPixels.reserveCapacity(size * size)

    pixelDataPointer.withMemoryRebound(to: UInt32.self, capacity: height * pixelsPerRow) { pixelBuffer in
      for rowOffset in -halfSize...halfSize {
        let samplePixelY = max(0, min(clampedTargetPixelY + rowOffset, height - 1))
        let rowStartBufferIndex = samplePixelY * pixelsPerRow

        for colOffset in -halfSize...halfSize {
          let samplePixelX = max(0, min(clampedTargetPixelX + colOffset, width - 1))
          sampledPixels.append(pixelBuffer[rowStartBufferIndex + samplePixelX])
        }
      }
    }

    return try SampleGrid(size: size, colorSpace: sourceColorSpace, pixels: sampledPixels)
  }
}

enum ScreenCaptureService {
  enum Error: Swift.Error, LocalizedError {
    case displayNotFound
    case missingSdrImage

    var errorDescription: String? {
      switch self {
      case .displayNotFound: "Display not found in shareable content."
      case .missingSdrImage: "Captured screenshot is missing SDR image representation."
      }
    }
  }

  nonisolated static func capture(screen: NSScreen, targetColorSpace: OutputColorSpace) async throws -> ScreenCapture {
    let availableContent = try await SCShareableContent.current

    guard let display = availableContent.displays.first(where: { $0.displayID == screen.cgDirectDisplayID }) else {
      throw Error.displayNotFound
    }

    let contentFilter = SCContentFilter(
      display: display,
      including: availableContent.applications.filter { application in
        application.processID != NSRunningApplication.current.processIdentifier
      },
      exceptingWindows: []
    )

    let configuration = SCStreamConfiguration()
    configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
    configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
    configuration.showsCursor = false

    if targetColorSpace == .sRGB {
      configuration.colorSpaceName = CGColorSpace.sRGB
    }

    let image = try await SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration)

    return try ScreenCapture(image: image, scaleFactor: screen.backingScaleFactor)
  }
}

struct ColorSamplePresentation {
  let mouseLocation: CGPoint
  let sampleGrid: SampleGrid
  let outputString: String
  let detailString: String
}

enum ColorSampleRenderer {
  private static let gridPath: CGPath = {
    let path = CGMutablePath()
    let loupeSize = CGFloat(Configuration.gridSize) * Configuration.magnification
    let magnification = Configuration.magnification

    for index in 0...Configuration.gridSize {
      let offset = CGFloat(index) * magnification

      path.move(to: CGPoint(x: offset, y: 0))
      path.addLine(to: CGPoint(x: offset, y: loupeSize))
      path.move(to: CGPoint(x: 0, y: offset))
      path.addLine(to: CGPoint(x: loupeSize, y: offset))
    }

    return path.copy()!
  }()

  private static let centerCellRect = CGRect(
    x: CGFloat(Configuration.gridSize / 2) * Configuration.magnification,
    y: CGFloat(Configuration.gridSize / 2) * Configuration.magnification,
    width: Configuration.magnification,
    height: Configuration.magnification
  )

  private static var loupeSize: CGFloat { CGFloat(Configuration.gridSize) * Configuration.magnification }

  static func draw(presentation: ColorSamplePresentation, in bounds: CGRect) {
    let loupeRect = CGRect(
      x: floor(presentation.mouseLocation.x - loupeSize / 2),
      y: floor(presentation.mouseLocation.y - loupeSize / 2),
      width: loupeSize,
      height: loupeSize
    )

    drawLoupe(for: presentation, in: loupeRect)
    drawLabel(for: presentation, below: loupeRect, in: bounds)
  }

  private static func drawLoupe(for presentation: ColorSamplePresentation, in loupeRect: CGRect) {
    guard let context = NSGraphicsContext.current?.cgContext else {
      return
    }

    context.saveGState()

    let loupePath = CGPath(
      roundedRect: loupeRect,
      cornerWidth: Configuration.loupeCornerRadius,
      cornerHeight: Configuration.loupeCornerRadius,
      transform: nil
    )
    context.addPath(loupePath)
    context.clip()
    context.setShouldAntialias(false)
    context.interpolationQuality = .none

    context.draw(presentation.sampleGrid.loupeImage, in: loupeRect)

    context.saveGState()
    context.translateBy(x: loupeRect.minX, y: loupeRect.minY)

    context.setStrokeColor(Configuration.gridLineColor.cgColor)
    context.setLineWidth(1.0)

    context.addPath(gridPath)
    context.strokePath()

    context.setLineWidth(1.0)

    context.setStrokeColor(Configuration.reticleInnerColor.cgColor)
    context.stroke(centerCellRect.insetBy(dx: 0.5, dy: 0.5))

    context.setStrokeColor(Configuration.reticleOuterColor.cgColor)
    context.stroke(centerCellRect.insetBy(dx: -0.5, dy: -0.5))

    context.restoreGState()
    context.restoreGState()

    context.setShouldAntialias(true)

    let borderPath = CGPath(
      roundedRect: loupeRect,
      cornerWidth: Configuration.loupeCornerRadius + 1.0,
      cornerHeight: Configuration.loupeCornerRadius + 1.0,
      transform: nil
    )
    context.addPath(borderPath)
    context.setStrokeColor(Configuration.borderColor.cgColor)
    context.setLineWidth(4.0)
    context.strokePath()
  }

  private static func drawLabel(for presentation: ColorSamplePresentation, below loupeRect: CGRect, in bounds: CGRect) {
    let valueAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedSystemFont(ofSize: Configuration.valueFontSize, weight: .semibold),
      .foregroundColor: Configuration.valueForegroundColor
    ]
    let detailAttributes: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: Configuration.detailFontSize, weight: .regular),
      .foregroundColor: Configuration.detailForegroundColor
    ]
    let lines = [
      NSAttributedString(string: presentation.outputString, attributes: valueAttributes),
      NSAttributedString(string: presentation.detailString, attributes: detailAttributes)
    ]
    let lineSizes = lines.map { $0.size() }
    let labelWidth = (lineSizes.map(\.width).max() ?? 0.0) + Configuration.labelHorizontalPadding * 2.0
    let labelHeight =
      lineSizes.map(\.height).reduce(0.0, +)
      + CGFloat(max(0, lines.count - 1)) * Configuration.labelLineSpacing
      + Configuration.labelVerticalPadding * 2.0

    var labelOriginY = loupeRect.minY - labelHeight - Configuration.labelMargin

    if labelOriginY < bounds.minY + Configuration.labelMargin {
      labelOriginY = loupeRect.maxY + Configuration.labelMargin
    }

    let labelRect = CGRect(
      x: presentation.mouseLocation.x - labelWidth / 2.0,
      y: labelOriginY,
      width: labelWidth,
      height: labelHeight
    ).integral
    let labelPath = NSBezierPath(
      roundedRect: labelRect,
      xRadius: Configuration.labelCornerRadius,
      yRadius: Configuration.labelCornerRadius
    )

    Configuration.labelBackgroundColor.setFill()
    labelPath.fill()

    var currentY = labelRect.maxY - Configuration.labelVerticalPadding

    for (line, lineSize) in zip(lines, lineSizes) {
      currentY -= lineSize.height
      line.draw(at: CGPoint(x: labelRect.midX - lineSize.width / 2.0, y: currentY))
      currentY -= Configuration.labelLineSpacing
    }
  }
}

final class OverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
}

@MainActor
protocol ColorSamplerViewDelegate: AnyObject {
  func colorSamplerView(_ view: ColorSamplerView, didReceive event: ColorSamplerView.Event)
}

@MainActor
final class ColorSamplerView: NSView {
  enum Event {
    case mouseMoved(CGPoint)
    case mouseDown
    case keyDown(NSEvent)
  }

  weak var delegate: ColorSamplerViewDelegate?

  var presentation: ColorSamplePresentation?

  override var acceptsFirstResponder: Bool { true }

  private var mouseTrackingArea: NSTrackingArea?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    DispatchQueue.main.async {
      NSCursor.hide()
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()

    if let mouseTrackingArea {
      removeTrackingArea(mouseTrackingArea)
    }

    let mouseTrackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .inVisibleRect, .mouseMoved, .cursorUpdate],
      owner: self,
      userInfo: nil
    )

    self.mouseTrackingArea = mouseTrackingArea

    addTrackingArea(mouseTrackingArea)
  }

  override func cursorUpdate(with event: NSEvent) {
    NSCursor.hide()
  }

  override func mouseMoved(with event: NSEvent) {
    NSCursor.hide()
    delegate?.colorSamplerView(self, didReceive: .mouseMoved(event.locationInWindow))
  }

  override func mouseDown(with event: NSEvent) {
    delegate?.colorSamplerView(self, didReceive: .mouseDown)
  }

  override func keyDown(with event: NSEvent) {
    delegate?.colorSamplerView(self, didReceive: .keyDown(event))
  }

  override func draw(_ dirtyRect: NSRect) {
    guard let presentation else {
      return
    }

    ColorSampleRenderer.draw(presentation: presentation, in: bounds)
  }
}

@MainActor
final class ColorSamplerSession {
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

  private let colorSamplerView = ColorSamplerView()
  private let overlayWindow: OverlayWindow
  private let options: ColorSamplerOptions
  private var displayID: CGDirectDisplayID
  private var currentSpaceID: SpaceID
  private var workspaceObservationTask: Task<Void, Never>?
  private var screenCaptureTask: Task<Void, Never>?
  private var screenCapture: ScreenCapture?

  private var presentation: ColorSamplePresentation? {
    didSet {
      updateColorSamplerView()
    }
  }

  private var lastKnownMouseLocation: CGPoint?

  init(options: ColorSamplerOptions, screen: NSScreen) throws {
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
    window.contentView = colorSamplerView
    window.collectionBehavior = [.ignoresCycle, .stationary, .auxiliary, .canJoinAllSpaces]
    window.level = .screenSaver
    window.backgroundColor = .clear
    window.ignoresMouseEvents = false

    self.overlayWindow = window
    self.displayID = displayID
    self.currentSpaceID = currentSpaceID
    self.options = options
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

        for name in [
          NSWorkspace.didActivateApplicationNotification,
          NSWorkspace.didHideApplicationNotification,
          NSWorkspace.didUnhideApplicationNotification
        ] {
          group.addTask { @MainActor [weak self] in
            for await _ in NSWorkspace.shared.notificationCenter.notifications(named: name) {
              self?.captureScreenAndSampleColor()
            }
          }
        }

        group.addTask { @MainActor [weak self] in
          for await _ in DistributedNotificationCenter.default().notifications(
            named: Notification.Name("AppleInterfaceThemeChangedNotification")
          ) {
            self?.captureScreenAndSampleColor()
          }
        }
      }
    }

    colorSamplerView.delegate = self

    NSApplication.shared.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)

    captureScreenAndSampleColor()
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
    captureScreenAndSampleColor()
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
    captureScreenAndSampleColor()
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
    captureScreenAndSampleColor()
  }

  private func handleMouseMoved(to location: CGPoint) {
    self.lastKnownMouseLocation = location
    updatePresentation()
  }

  private func handleMouseDown() {
    guard let presentation else {
      NSApplication.shared.terminate(nil)
      return
    }

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(presentation.outputString, forType: .string)

    print(presentation.outputString)

    NSApplication.shared.terminate(nil)
  }

  private func handleKeyPressed(_ event: NSEvent) {
    if event.keyCode == 53 {
      NSApplication.shared.terminate(nil)
      return
    }

    if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" {
      captureScreenAndSampleColor(flicker: true)
    }
  }

  private func captureScreenAndSampleColor(flicker: Bool = false) {
    if flicker {
      self.screenCapture = nil
      self.presentation = nil
    }

    screenCaptureTask?.cancel()
    self.screenCaptureTask = Task { [weak self, displayID, targetColorSpace = options.colorSpace] in
      do {
        guard let screen = NSScreen.screen(for: displayID) else {
          return
        }

        let screenCapture = try await ScreenCaptureService.capture(screen: screen, targetColorSpace: targetColorSpace)

        guard let self, !Task.isCancelled else {
          return
        }

        self.screenCaptureTask = nil
        self.screenCapture = screenCapture

        updatePresentation()
      } catch {
        FileHandle.standardError.write(Data(("Failed to capture screen: \(error.localizedDescription)\n").utf8))
        NSApplication.shared.terminate(nil)
      }
    }
  }

  private func updatePresentation() {
    guard
      let screenCapture,
      let mouseLocation = lastKnownMouseLocation
        ?? (NSScreen.screen(for: displayID)?.frame.contains(NSEvent.mouseLocation) ?? false
          ? NSEvent.mouseLocation
          : nil)
    else {
      return
    }

    do {
      let sampleGrid = try screenCapture.sampleGrid(at: mouseLocation, size: Configuration.gridSize)

      guard let centerSample = sampleGrid.centerSample else {
        return
      }

      self.presentation = ColorSamplePresentation(
        mouseLocation: mouseLocation,
        sampleGrid: sampleGrid,
        outputString: centerSample.formattedString(for: options.outputFormat),
        detailString: sampleGrid.colorSpace.displayName
      )
    } catch {
      FileHandle.standardError.write(Data(("Failed to sample color: \(error.localizedDescription)\n").utf8))
      NSApplication.shared.terminate(nil)
    }
  }

  private func updateColorSamplerView() {
    colorSamplerView.presentation = presentation
    colorSamplerView.needsDisplay = true
  }
}

extension ColorSamplerSession: ColorSamplerViewDelegate {
  func colorSamplerView(_ view: ColorSamplerView, didReceive event: ColorSamplerView.Event) {
    switch event {
    case .mouseMoved(let location): handleMouseMoved(to: location)
    case .mouseDown: handleMouseDown()
    case .keyDown(let event): handleKeyPressed(event)
    }
  }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let colorSamplerOptions: ColorSamplerOptions
  private var colorSamplerSession: ColorSamplerSession?
  private var systemSampler: NSColorSampler?

  init(colorSamplerOptions: ColorSamplerOptions) {
    self.colorSamplerOptions = colorSamplerOptions
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    if colorSamplerOptions.useSystemSampler {
      runSystemSampler()
    } else {
      guard let screen = NSScreen.screenContainingMouse ?? .main else {
        FileHandle.standardError.write(Data("Failed to determine screen for color sampling session.\n".utf8))
        exit(EXIT_FAILURE)
      }

      do {
        self.colorSamplerSession = try ColorSamplerSession(options: colorSamplerOptions, screen: screen)
        observeIPCCommands()
      } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        exit(EXIT_FAILURE)
      }
    }

    observeIPCCommands()
  }

  private func runSystemSampler() {
    NSApplication.shared.activate(ignoringOtherApps: true)
    NSColorSampler().show { [colorSamplerOptions] color in
      guard let color else {
        NSApplication.shared.terminate(nil)
        return
      }

      let targetColorSpace =
        colorSamplerOptions.colorSpace == .sRGB
        ? CGColorSpace(name: CGColorSpace.sRGB)
        : color.cgColor.colorSpace
      let convertedCGColor =
        targetColorSpace.map { targetColorSpace in
          color.cgColor.converted(
            to: targetColorSpace,
            intent: .relativeColorimetric,
            options: nil
          ) ?? color.cgColor
        } ?? color.cgColor

      guard let components = convertedCGColor.components, components.count >= 3 else {
        NSApplication.shared.terminate(nil)
        return
      }

      let red = UInt8(max(0, min(255, Int((components[0] * 255.0).rounded()))))
      let green = UInt8(max(0, min(255, Int((components[1] * 255.0).rounded()))))
      let blue = UInt8(max(0, min(255, Int((components[2] * 255.0).rounded()))))
      let sample = ColorSample(red: red, green: green, blue: blue)
      let outputString = sample.formattedString(for: colorSamplerOptions.outputFormat)

      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(outputString, forType: .string)

      print(outputString)

      NSApplication.shared.terminate(nil)
    }
  }

  private func observeIPCCommands() {
    Task {
      let notificationCenter = DistributedNotificationCenter.default()

      for await notification in notificationCenter.notifications(named: IPCCommand.notificationName) {
        if let command = IPCCommand(userInfo: notification.userInfo) {
          handleIPCCommand(command)
        }
      }
    }
  }

  private func handleIPCCommand(_ command: IPCCommand) {
    switch command {
    case .activate:
      if colorSamplerOptions.useSystemSampler {
        NSApplication.shared.activate(ignoringOtherApps: true)
      } else {
        guard let screen = NSScreen.screenContainingMouse ?? .main else {
          return
        }

        colorSamplerSession?.move(to: screen)
        NSApplication.shared.activate(ignoringOtherApps: true)
      }
    }
  }
}

enum IPCCommand {
  case activate

  static let notificationName = Notification.Name("industries.britown.SampleColor.IPCCommand")

  init?(userInfo: [AnyHashable: Any]?) {
    guard let userInfo = userInfo as? [String: String] else {
      return nil
    }

    switch userInfo["command"] {
    case "activate": self = .activate
    default: return nil
    }
  }

  func send() {
    var userInfo: [String: String] = [:]

    switch self {
    case .activate:
      userInfo["command"] = "activate"
    }

    DistributedNotificationCenter.default().postNotificationName(
      Self.notificationName,
      object: nil,
      userInfo: userInfo,
      deliverImmediately: true
    )
  }
}

let usageDescription = """
  Usage:
    \(ProcessInfo.processInfo.processName) [options]

  Options:
    --hex             Output color as hexadecimal (default)
    --rgb             Output color as RGB
    --srgb            Convert colors to the sRGB color space (default)
    --native          Output colors in the display's native color space without conversion
    --system-sampler  Use the native macOS color sampler instead of the custom loupe
    -h, --help        Show this help message
  """

var parsedOutputFormat = ColorSamplerOptions.default.outputFormat
var parsedColorSpace = ColorSamplerOptions.default.colorSpace
var parsedUseSystemSampler = ColorSamplerOptions.default.useSystemSampler

for argument in Array(CommandLine.arguments.dropFirst()) {
  switch argument.lowercased() {
  case "--hex":
    parsedOutputFormat = .hex

  case "--rgb":
    parsedOutputFormat = .rgb

  case "--srgb":
    parsedColorSpace = .sRGB

  case "--native":
    parsedColorSpace = .native

  case "--system-sampler":
    parsedUseSystemSampler = true

  case "-h", "--help":
    print(usageDescription)
    exit(EXIT_SUCCESS)

  default:
    FileHandle.standardError.write(Data("Unknown argument: \(argument)\n\n\(usageDescription)\n".utf8))
    exit(EX_USAGE)
  }
}

let colorSamplerOptions = ColorSamplerOptions(
  outputFormat: parsedOutputFormat,
  colorSpace: parsedColorSpace,
  useSystemSampler: parsedUseSystemSampler
)

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
    let delegate = AppDelegate(colorSamplerOptions: colorSamplerOptions)
    let application = NSApplication.shared
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
  }
} else {
  IPCCommand.activate.send()
  exit(EXIT_SUCCESS)
}
