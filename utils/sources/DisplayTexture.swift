// Shared: Agent Log

import AppKit
import CoreImage.CIFilterBuiltins

enum Configuration {
  static let subsystem = "industries.britown.DisplayTexture"
  static let lightAppearanceStyle = TextureStyle(
    grainSize: 1.0,
    grainSoftness: 0.5,
    grainContrast: 1.5,
    grainOpacity: 0.03,
    tintColor: .clear
  )
  static let darkAppearanceStyle = TextureStyle(
    grainSize: 1.0,
    grainSoftness: 0.5,
    grainContrast: 1.5,
    grainOpacity: 0.02,
    tintColor: NSColor(white: 0.5, alpha: 0.02)
  )
}

extension NSAppearance {
  var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

struct TextureStyle: Sendable {
  let grainSize: CGFloat // Points
  let grainSoftness: CGFloat // Gaussian blur radius in points
  let grainContrast: Float
  let grainOpacity: Float
  let tintColor: NSColor

  var grain: Texture.Grain { Texture.Grain(size: grainSize, softness: grainSoftness, contrast: grainContrast) }

  static func forAppearance(_ appearance: NSAppearance) -> TextureStyle {
    return appearance.isDark ? Configuration.darkAppearanceStyle : Configuration.lightAppearanceStyle
  }
}

struct Texture: Sendable {
  enum Error: Swift.Error, LocalizedError {
    case failedToRenderTexture(Descriptor)

    var errorDescription: String? {
      switch self {
      case .failedToRenderTexture(let descriptor): "Failed to render \(descriptor) texture."
      }
    }
  }

  struct Metrics: Hashable, Sendable, CustomStringConvertible {
    let pixelWidth: Int
    let pixelHeight: Int
    let scaleFactor: CGFloat

    var description: String { "\(pixelWidth)x\(pixelHeight) @\(scaleFactor.formatted())x" }

    init(screen: NSScreen) {
      self.pixelWidth = Int((screen.frame.width * screen.backingScaleFactor).rounded(.up))
      self.pixelHeight = Int((screen.frame.height * screen.backingScaleFactor).rounded(.up))
      self.scaleFactor = screen.backingScaleFactor
    }
  }

  struct Grain: Hashable, Sendable, CustomStringConvertible {
    let size: CGFloat
    let softness: CGFloat
    let contrast: Float

    var description: String {
      "size \(size.formatted())pt, softness \(softness.formatted())pt, contrast \(contrast.formatted())"
    }
  }

  struct Descriptor: Hashable, Sendable, CustomStringConvertible {
    let metrics: Metrics
    let grain: Grain

    var description: String { "\(metrics) (\(grain))" }
  }

  let descriptor: Descriptor
  let image: CGImage

  @concurrent
  static func render(for descriptors: Set<Descriptor>) async throws -> [Descriptor: Texture] {
    let context = CIContext(options: [.cacheIntermediates: false, .allowLowPower: true, .workingColorSpace: NSNull()])
    let colorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2) ?? CGColorSpaceCreateDeviceGray()

    var textures: [Descriptor: Texture] = [:]

    for descriptor in descriptors {
      guard let randomImage = CIFilter.randomGenerator().outputImage else {
        throw Error.failedToRenderTexture(descriptor)
      }

      let pointScale = CGAffineTransform(
        scaleX: descriptor.grain.size * descriptor.metrics.scaleFactor,
        y: descriptor.grain.size * descriptor.metrics.scaleFactor
      )

      let blurFilter = CIFilter.gaussianBlur()
      blurFilter.inputImage = randomImage.settingAlphaOne(in: .infinite).transformed(by: pointScale)
      blurFilter.radius = Float(descriptor.grain.softness * descriptor.metrics.scaleFactor)

      let contrastFilter = CIFilter.colorControls()
      contrastFilter.inputImage = blurFilter.outputImage
      contrastFilter.contrast = descriptor.grain.contrast
      contrastFilter.saturation = 0

      guard
        let textureImage = contrastFilter.outputImage,
        let image = context.createCGImage(
          textureImage,
          from: CGRect(x: 0, y: 0, width: descriptor.metrics.pixelWidth, height: descriptor.metrics.pixelHeight),
          format: .L8,
          colorSpace: colorSpace
        )
      else {
        throw Error.failedToRenderTexture(descriptor)
      }

      textures[descriptor] = Texture(descriptor: descriptor, image: image)
    }

    return textures
  }
}

final class TextureWindow: NSWindow {
  private(set) var texture: Texture

  private let rootLayer = CALayer()
  private let textureLayer = CALayer()

  init(screen: NSScreen, texture: Texture, style: TextureStyle) {
    self.texture = texture

    super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

    rootLayer.addSublayer(textureLayer)

    let contentView = NSView()
    contentView.layer = rootLayer
    contentView.wantsLayer = true

    textureLayer.contentsGravity = .bottomLeft

    self.contentView = contentView
    self.isOpaque = false
    self.backgroundColor = .clear
    self.hasShadow = false
    self.ignoresMouseEvents = true
    self.level = .screenSaver
    self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    self.sharingType = .none
    self.animationBehavior = .none
    self.canHide = false
    self.isExcludedFromWindowsMenu = true
    self.isReleasedWhenClosed = false

    update(screen: screen, texture: texture)
    apply(style)
  }

  func update(screen: NSScreen, texture: Texture) {
    self.texture = texture

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    setFrame(screen.frame, display: false)
    textureLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
    textureLayer.contentsScale = texture.descriptor.metrics.scaleFactor
    textureLayer.contents = texture.image

    CATransaction.commit()
  }

  func apply(_ style: TextureStyle) {
    CATransaction.begin()
    CATransaction.setDisableActions(true)

    rootLayer.backgroundColor = style.tintColor.cgColor
    textureLayer.opacity = style.grainOpacity

    CATransaction.commit()
  }
}

@MainActor
final class TextureOverlayManager {
  private(set) var isEnabled = false

  private let startDate = Date.now
  private let screenParametersUpdateDebounceInterval: Duration = .milliseconds(250)
  private var style = TextureStyle.forAppearance(NSApplication.shared.effectiveAppearance)
  private var windows: [CGDirectDisplayID: TextureWindow] = [:]
  private var appearanceObservation: NSKeyValueObservation?
  private var screenParametersObservationTask: Task<Void, Never>?
  private var updateTask: Task<Void, Never>?

  init() {
    self.appearanceObservation = NSApplication.shared.observe(\.effectiveAppearance) { [weak self] _, _ in
      MainActor.assumeIsolated {
        self?.applyStyle(.forAppearance(NSApplication.shared.effectiveAppearance))
      }
    }

    self.screenParametersObservationTask = Task { [weak self] in
      for await _ in NotificationCenter.default.notifications(
        named: NSApplication.didChangeScreenParametersNotification
      ) {
        guard let self else {
          break
        }

        if isEnabled {
          scheduleUpdate(after: screenParametersUpdateDebounceInterval)
        }
      }
    }
  }

  isolated deinit {
    appearanceObservation?.invalidate()
    screenParametersObservationTask?.cancel()
    updateTask?.cancel()
    removeWindows(for: Array(windows.keys))
  }

  func setEnabled(_ isEnabled: Bool) {
    self.isEnabled = isEnabled

    if isEnabled {
      scheduleUpdate()
    } else {
      updateTask?.cancel()
      removeWindows(for: Array(windows.keys))
    }
  }

  func toggleEnabled() {
    setEnabled(!isEnabled)
  }

  func logDiagnosticReport() {
    let windowsInfo = windows.sorted { $0.key < $1.key }.map { displayID, window in
      "  Display \(displayID): frame \(window.frame), texture \(window.texture.descriptor), visible: \(window.isVisible)"
    }

    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Enabled: \(isEnabled)
        Appearance: \(NSApplication.shared.effectiveAppearance.isDark ? "dark" : "light")
        Update pending: \(updateTask != nil)
        Windows: \(windows.count)
      \(windowsInfo.map { "  \($0)" }.joined(separator: "\n"))
      """
    )
  }

  private func applyStyle(_ style: TextureStyle) {
    let hasGrainChanged = style.grain != self.style.grain

    self.style = style

    if hasGrainChanged, isEnabled {
      scheduleUpdate()
    } else {
      for window in windows.values {
        window.apply(style)
      }
    }
  }

  private func scheduleUpdate(after delay: Duration = .zero) {
    updateTask?.cancel()
    self.updateTask = Task { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }

      guard !Task.isCancelled else {
        return
      }

      await self?.updateWindows()

      if !Task.isCancelled {
        self?.updateTask = nil
      }
    }
  }

  private func updateWindows() async {
    let screens = Dictionary(
      NSScreen.screens.compactMap { screen in screen.cgDirectDisplayID.map { ($0, screen) } },
      uniquingKeysWith: { first, _ in first }
    )
    let requiredDescriptors = Set(
      screens.values.map { Texture.Descriptor(metrics: Texture.Metrics(screen: $0), grain: style.grain) }
    )

    var textures = Dictionary(
      windows.values.map { ($0.texture.descriptor, $0.texture) },
      uniquingKeysWith: { first, _ in first }
    ).filter { requiredDescriptors.contains($0.key) }

    let missingDescriptors = requiredDescriptors.subtracting(textures.keys)

    if !missingDescriptors.isEmpty {
      do {
        textures.merge(try await Texture.render(for: missingDescriptors)) { _, new in new }
      } catch {
        Log.error(error.localizedDescription)
        return
      }
    }

    guard !Task.isCancelled, isEnabled else {
      return
    }

    removeWindows(for: windows.keys.filter { screens[$0] == nil })

    for (displayID, screen) in screens {
      guard
        let texture = textures[Texture.Descriptor(metrics: Texture.Metrics(screen: screen), grain: style.grain)]
      else {
        continue
      }

      if let window = windows[displayID] {
        window.update(screen: screen, texture: texture)
        window.apply(style)
      } else {
        let window = TextureWindow(screen: screen, texture: texture, style: style)
        window.orderFrontRegardless()

        self.windows[displayID] = window
      }
    }
  }

  private func removeWindows(for displayIDs: [CGDirectDisplayID]) {
    for displayID in displayIDs {
      windows.removeValue(forKey: displayID)?.close()
    }
  }
}

@MainActor
final class AppDelegate: NSObject, AgentDelegate {
  private var textureOverlayManager: TextureOverlayManager?

  func applicationDidFinishLaunching(_ notification: Notification) {
    self.textureOverlayManager = TextureOverlayManager()
    textureOverlayManager?.setEnabled(true)
  }

  func applicationWillTerminate(_ notification: Notification) {
    self.textureOverlayManager = nil
  }

  func handleIPCCommand(_ ipcCommand: IPCCommand) {
    switch ipcCommand {
    case .toggle: textureOverlayManager?.toggleEnabled()
    case .printLog: textureOverlayManager?.logDiagnosticReport()
    case .quit: NSApplication.shared.terminate(nil)
    }
  }
}

enum IPCCommand: String, AgentIPCCommand {
  case toggle
  case printLog = "print-log"
  case quit
}

@main
enum DisplayTexture {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .accessory) {
      AppDelegate()
    }
  }
}
