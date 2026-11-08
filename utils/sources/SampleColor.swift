// Shared: CommandLineOptions Comparable EventTap Log NSScreen SCShareableContent ScreenCapturePermission

import AppKit
import ScreenCaptureKit

enum Configuration {
  static let labelForegroundColor: NSColor = .white
  static let labelBackgroundColor: NSColor = .systemRed
  static let labelMargin: CGFloat = 6.0
  static let labelCornerRadius: CGFloat = 4.0
  static let labelPadding: (horizontal: CGFloat, vertical: CGFloat) = (4.0, 2.0)
  static let labelOffset: CGFloat = 8.0
  static let idleCaptureInterval: Duration = .milliseconds(100)
  static let captureSettleDuration: Duration = .milliseconds(100)
}

struct HexIntegerFormatStyle<Value: BinaryInteger>: FormatStyle {
  typealias FormatInput = Value
  typealias FormatOutput = String

  var padToLength: Int
  var uppercase: Bool

  func format(_ value: Value) -> String {
    let string = String(value, radix: 16, uppercase: uppercase)
    return String(repeating: "0", count: max(0, padToLength - string.count)) + string
  }
}

extension FormatStyle {
  static func hex<Value>(padTo length: Int = 2, uppercase: Bool = false) -> Self
  where Self == HexIntegerFormatStyle<Value> {
    return HexIntegerFormatStyle(padToLength: length, uppercase: uppercase)
  }
}

struct RGBFormatStyle: FormatStyle {
  typealias FormatInput = NSColor
  typealias FormatOutput = String

  enum Representation: Hashable, Codable {
    case hex
    case rgb
  }

  var representation: Representation

  func format(_ value: NSColor) -> String {
    let red = Self.byte(value.redComponent)
    let green = Self.byte(value.greenComponent)
    let blue = Self.byte(value.blueComponent)

    switch representation {
    case .hex: return "#\(red.formatted(.hex()))\(green.formatted(.hex()))\(blue.formatted(.hex()))"
    case .rgb: return "rgb(\(red), \(green), \(blue))"
    }
  }

  private static func byte(_ component: CGFloat) -> UInt8 {
    return UInt8(Int((component * 255).rounded()).clamped(to: 0...255))
  }
}

extension FormatStyle where Self == RGBFormatStyle {
  static var hex: RGBFormatStyle { RGBFormatStyle(representation: .hex) }
  static var rgb: RGBFormatStyle { RGBFormatStyle(representation: .rgb) }
}

extension NSColor {
  func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == NSColor {
    return style.format(self)
  }
}

// Content filters are reused across captures and are immutable after creation.
extension SCContentFilter: @retroactive @unchecked Sendable {}

enum PixelCapture {
  enum Error: Swift.Error, LocalizedError {
    case unsupportedColorSpace
    case pixelOutOfBounds
    case failedToCreateBitmapContext
    case pixelFullyTransparent

    var errorDescription: String? {
      switch self {
      case .unsupportedColorSpace: "Captured image has an unsupported color space."
      case .pixelOutOfBounds: "Pixel is outside the captured image."
      case .failedToCreateBitmapContext: "Failed to create bitmap context to read the captured pixel."
      case .pixelFullyTransparent: "Captured pixel is fully transparent."
      }
    }
  }

  private static let colorSamplerBundleIdentifier = "com.apple.appkit.xpc.ColorSampler"

  @concurrent
  static func contentFilter(
    for displayID: CGDirectDisplayID
  ) async throws -> (filter: SCContentFilter, excludesColorSampler: Bool) {
    let shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    let filter = try shareableContent.contentFilter(
      forDisplay: displayID,
      excludingBundleIdentifiers: [Self.colorSamplerBundleIdentifier]
    )

    return (
      filter,
      shareableContent.applications.contains { $0.bundleIdentifier == Self.colorSamplerBundleIdentifier }
    )
  }

  @concurrent
  static func color(
    at location: CGPoint,
    on screen: (frame: CGRect, scaleFactor: CGFloat),
    using contentFilter: SCContentFilter
  ) async throws -> NSColor {
    let pixelsPerPoint = max(1, Int(screen.scaleFactor.rounded()))
    let displayWidth = Int(screen.frame.width) * pixelsPerPoint
    let displayHeight = Int(screen.frame.height) * pixelsPerPoint

    // NSColorSampler picks the pixel at the rounded (not floored) pixel coordinate of the pointer.
    let pixelX = Int(((location.x - screen.frame.minX) * CGFloat(pixelsPerPoint)).rounded())
    let pixelYFromBottom = Int(((location.y - screen.frame.minY) * CGFloat(pixelsPerPoint)).rounded())
    let targetX = pixelX.clamped(to: 0...(displayWidth - 1))
    let targetY = (displayHeight - 1 - pixelYFromBottom).clamped(to: 0...(displayHeight - 1))

    let configuration = SCStreamConfiguration()
    // Capture the whole point containing the target pixel as source rects that aren't aligned to whole points produce
    // partially transparent pixels.
    configuration.sourceRect = CGRect(x: targetX / pixelsPerPoint, y: targetY / pixelsPerPoint, width: 1, height: 1)
    configuration.width = pixelsPerPoint
    configuration.height = pixelsPerPoint
    configuration.showsCursor = false

    let image = try await SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: configuration)

    return try color(ofPixelAt: (targetX % pixelsPerPoint, targetY % pixelsPerPoint), in: image)
  }

  private static func color(ofPixelAt pixel: (x: Int, y: Int), in image: CGImage) throws -> NSColor {
    guard
      let cgColorSpace = image.colorSpace,
      cgColorSpace.model == .rgb,
      let colorSpace = NSColorSpace(cgColorSpace: cgColorSpace)
    else {
      throw Error.unsupportedColorSpace
    }

    guard let pixelImage = image.cropping(to: CGRect(x: pixel.x, y: pixel.y, width: 1, height: 1)) else {
      throw Error.pixelOutOfBounds
    }

    var rgba: [UInt8] = [0, 0, 0, 0]

    let didDraw = rgba.withUnsafeMutableBytes { buffer in
      guard
        let context = CGContext(
          data: buffer.baseAddress,
          width: 1,
          height: 1,
          bitsPerComponent: 8,
          bytesPerRow: 4,
          space: cgColorSpace,
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        return false
      }

      context.draw(pixelImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

      return true
    }

    guard didDraw else {
      throw Error.failedToCreateBitmapContext
    }

    guard rgba[3] > 0 else {
      throw Error.pixelFullyTransparent
    }

    let alpha = CGFloat(rgba[3])
    let components = rgba.prefix(3).map { CGFloat($0) / alpha } + [1.0]

    return NSColor(colorSpace: colorSpace, components: components, count: components.count)
  }
}

final class LabelView: NSView {
  private static let labelFont: NSFont = .systemFont(ofSize: NSFont.labelFontSize, weight: .regular)

  private(set) var text = ""
  private(set) var labelSize: CGSize = .zero

  private var attributedString = NSAttributedString()

  func setText(_ text: String) {
    guard text != self.text else {
      return
    }

    let attributedString = NSAttributedString(
      string: text,
      attributes: [.font: Self.labelFont, .foregroundColor: Configuration.labelForegroundColor]
    )
    let textSize = attributedString.size()

    self.text = text
    self.attributedString = attributedString
    self.labelSize = CGSize(
      width: ceil(textSize.width) + Configuration.labelPadding.horizontal * 2,
      height: ceil(textSize.height) + Configuration.labelPadding.vertical * 2
    )
    self.needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    Configuration.labelBackgroundColor.setFill()
    NSBezierPath(
      roundedRect: bounds,
      xRadius: Configuration.labelCornerRadius,
      yRadius: Configuration.labelCornerRadius
    ).fill()
    attributedString.draw(at: CGPoint(x: Configuration.labelPadding.horizontal, y: Configuration.labelPadding.vertical))
  }
}

@MainActor
final class LiveColorPreview: NSObject {
  static let colorSamplerProcessName = "ColorSampler"
  static let colorSamplerLoupeRadius: CGFloat = 60.5

  private enum State {
    case idle
    case running
    case stopped
  }

  private let format: RGBFormatStyle
  private let colorSpace: NSColorSpace?
  private let window: NSWindow
  private let labelView = LabelView()
  private var eventTap: EventTap?
  private var displayLink: CADisplayLink?
  private var contentFilter: (displayID: CGDirectDisplayID, filter: SCContentFilter)?
  private var isLoupeVisible = false
  private var state: State = .idle
  private var captureTask: Task<Void, Never>?
  private var finishTask: Task<Void, Never>?
  private var lastMouseLocation: CGPoint?
  private var lastCapture: (location: CGPoint, time: ContinuousClock.Instant)?

  init(format: RGBFormatStyle, colorSpace: NSColorSpace?) {
    let window = NSWindow(
      // A window without a size isn't placed on a screen, so its display link never fires.
      contentRect: CGRect(x: 0, y: 0, width: 1, height: 1),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.collectionBehavior = [.ignoresCycle, .stationary, .canJoinAllSpaces, .fullScreenAuxiliary]
    window.level = .screenSaver
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.alphaValue = 0
    window.contentView = labelView

    self.format = format
    self.colorSpace = colorSpace
    self.window = window

    super.init()
  }

  func start() {
    guard state == .idle else {
      return
    }

    self.state = .running

    window.orderFrontRegardless()

    // NSColorSampler consumes pointer events, preventing event monitors from receiving them. An event tap still
    // receives them, but requires accessibility permission. Without accessibility permission the label updates only on
    // display-link ticks.
    if let eventTap = try? EventTap(
      location: .cghidEventTap,
      observing: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
    ) {
      eventTap.eventObserver = { [weak self] event in
        self?.handlePointer(at: Self.cocoaPoint(from: event.location))
      }
      eventTap.isEnabled = true

      self.eventTap = eventTap
    }

    let displayLink = labelView.displayLink(target: self, selector: #selector(displayLinkDidFire))
    displayLink.add(to: .main, forMode: .common)

    self.displayLink = displayLink
  }

  func stop() {
    guard state != .stopped else {
      return
    }

    self.state = .stopped

    hide()
  }

  func finish() async {
    if finishTask == nil {
      stop()

      // Wait for an in-progress capture before exiting as exiting immediately causes ScreenCaptureKit to show a permission prompt.
      self.finishTask = Task { [captureTask] in
        guard let captureTask else {
          return
        }

        await captureTask.value
        try? await Task.sleep(for: Configuration.captureSettleDuration)
      }
    }

    await finishTask?.value
  }

  private func hide() {
    displayLink?.invalidate()
    window.orderOut(nil)

    self.displayLink = nil
    self.eventTap = nil
  }

  @objc private func displayLinkDidFire(_ displayLink: CADisplayLink) {
    let mouseLocation = NSEvent.mouseLocation

    // NSColorSampler sometimes keeps its loupe hidden until the pointer moves.
    if !isLoupeVisible, Self.isLoupeOnScreen(near: mouseLocation) {
      self.isLoupeVisible = true
      updateVisibility()
    }

    handlePointer(at: mouseLocation)
  }

  private func handlePointer(at mouseLocation: CGPoint) {
    guard state == .running, let screen = NSScreen.screen(containing: mouseLocation) else {
      return
    }

    if mouseLocation != lastMouseLocation {
      self.lastMouseLocation = mouseLocation
      positionWindow(at: mouseLocation, on: screen)
    }

    captureIfNeeded(at: mouseLocation, on: screen)
  }

  private func captureIfNeeded(at mouseLocation: CGPoint, on screen: NSScreen) {
    guard captureTask == nil, let displayID = screen.cgDirectDisplayID else {
      return
    }

    if let lastCapture,
      lastCapture.location == mouseLocation,
      ContinuousClock.now - lastCapture.time < Configuration.idleCaptureInterval
    {
      return
    }

    let cachedContentFilter = contentFilter.flatMap { $0.displayID == displayID ? $0.filter : nil }

    self.lastCapture = (mouseLocation, .now)

    self.captureTask = Task { [weak self] in
      do {
        let filter: SCContentFilter

        if let cachedContentFilter {
          filter = cachedContentFilter
        } else {
          let result = try await PixelCapture.contentFilter(for: displayID)
          filter = result.filter

          if result.excludesColorSampler {
            self?.contentFilter = (displayID, result.filter)
          }
        }

        let color = try await PixelCapture.color(
          at: mouseLocation,
          on: (screen.frame, screen.backingScaleFactor),
          using: filter
        )

        guard let self, state == .running else {
          return
        }

        self.captureTask = nil

        update(with: color, on: screen)
        handlePointer(at: NSEvent.mouseLocation)
      } catch {
        guard let self, state == .running else {
          return
        }

        self.captureTask = nil

        if cachedContentFilter != nil {
          self.contentFilter = nil // May be stale (e.g. the display was reconfigured).
        } else {
          Log.error("Live preview unavailable: \(error.localizedDescription)")
          stop()
        }
      }
    }
  }

  private func update(with capturedColor: NSColor, on screen: NSScreen) {
    guard let color = colorSpace.map({ capturedColor.usingColorSpace($0) }) ?? capturedColor else {
      return
    }

    let text = color.formatted(format)

    guard text != labelView.text else {
      return
    }

    labelView.setText(text)

    if let lastMouseLocation {
      positionWindow(at: lastMouseLocation, on: screen)
    }

    updateVisibility()
  }

  private func updateVisibility() {
    window.alphaValue = isLoupeVisible && labelView.labelSize != .zero ? 1 : 0
  }

  private func positionWindow(at mouseLocation: CGPoint, on screen: NSScreen) {
    let labelSize = labelView.labelSize
    let screenFrame = screen.frame
    let offset = Self.colorSamplerLoupeRadius + Configuration.labelOffset
    var originY = mouseLocation.y - offset - labelSize.height

    if originY < screenFrame.minY + Configuration.labelMargin {
      originY = mouseLocation.y + offset
    }

    let originX = (mouseLocation.x - labelSize.width / 2).clamped(
      to: (screenFrame.minX + Configuration.labelMargin)...max(
        screenFrame.minX + Configuration.labelMargin,
        screenFrame.maxX - labelSize.width - Configuration.labelMargin
      )
    )

    let origin = CGPoint(x: round(originX), y: round(originY))

    if window.frame.size == labelSize {
      window.setFrameOrigin(origin)
    } else {
      window.setFrame(CGRect(origin: origin, size: labelSize), display: false)
    }
  }

  private static func cocoaPoint(from quartzPoint: CGPoint) -> CGPoint {
    return CGPoint(x: quartzPoint.x, y: (NSScreen.screens.first?.frame.height ?? 0) - quartzPoint.y)
  }

  private static func isLoupeOnScreen(near mouseLocation: CGPoint) -> Bool {
    guard
      let windowsInfo = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return false
    }

    return windowsInfo.contains { windowInfo in
      guard
        windowInfo[kCGWindowOwnerName as String] as? String == Self.colorSamplerProcessName,
        // The loupe is at cursor level; the sampler's full-screen windows are above it.
        windowInfo[kCGWindowLayer as String] as? CGWindowLevel == CGWindowLevelForKey(.cursorWindow),
        let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
        let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
      else {
        return false
      }

      // While hidden, the loupe is parked off-screen.
      let center = cocoaPoint(from: CGPoint(x: bounds.midX, y: bounds.midY))

      return abs(center.x - mouseLocation.x) <= bounds.width && abs(center.y - mouseLocation.y) <= bounds.height
    }
  }
}

struct CommandLineOptions: ParsableCommandLineOptions {
  static let usageDescription = """
    Usage:
      \(ProcessInfo.processInfo.processName) [options]

    Options:
      -f, --format <format>      Output format: 'hex' (default) or 'rgb'
      -c, --color-space <space>  Color space: 'srgb' (default) or 'native'
      -h, --help                 Show this help message
    """

  private(set) var format: RGBFormatStyle = .hex
  private(set) var colorSpace: NSColorSpace? = .sRGB

  init(arguments: some Sequence<String>) throws(CommandLineOptionsError) {
    var arguments = arguments.makeIterator()

    while let argument = arguments.next() {
      switch argument.lowercased() {
      case "-f", "--format":
        switch arguments.next()?.lowercased() {
        case "hex": self.format = .hex
        case "rgb": self.format = .rgb
        case .some(let value): throw .invalidUsage("Invalid format '\(value)'. Expected 'hex' or 'rgb'.")
        case .none: throw .invalidUsage("Missing value for '\(argument)'.")
        }

      case "-c", "--color-space":
        switch arguments.next()?.lowercased() {
        case "srgb": self.colorSpace = .sRGB
        case "native": self.colorSpace = nil
        case .some(let value): throw .invalidUsage("Invalid color space '\(value)'. Expected 'srgb' or 'native'.")
        case .none: throw .invalidUsage("Missing value for '\(argument)'.")
        }

      case "-h", "--help":
        throw .helpRequested

      default:
        throw .invalidUsage("Unknown argument: \(argument)")
      }
    }
  }
}

@main
enum SampleColor {
  static func main() {
    let options = CommandLineOptions.parseOrExit()
    let liveColorPreview =
      ScreenCapturePermission.isGranted
      ? LiveColorPreview(format: options.format, colorSpace: options.colorSpace)
      : nil

    NSColorSampler().show { [format = options.format, colorSpace = options.colorSpace] color in
      let exitCode = output(color, format: format, colorSpace: colorSpace)

      Task { @MainActor in
        await liveColorPreview?.finish()
        exit(exitCode)
      }
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)

    liveColorPreview?.start()

    withExtendedLifetime(liveColorPreview) {
      application.run()
    }
  }

  private static func output(_ color: NSColor?, format: RGBFormatStyle, colorSpace: NSColorSpace?) -> Int32 {
    guard let color else {
      return EXIT_SUCCESS
    }

    guard let color = colorSpace.map({ color.usingColorSpace($0) }) ?? color else {
      Log.error("Failed to convert color to the specified color space.")
      return EXIT_FAILURE
    }

    let result = color.formatted(format)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(result, forType: .string)

    print(result)

    return EXIT_SUCCESS
  }
}
