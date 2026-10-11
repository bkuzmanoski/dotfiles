// Shared: Agent Log

import AppKit
import CoreImage.CIFilterBuiltins

enum Configuration {
  static let subsystem = "industries.britown.DisplayTexture"
  static let grainSize: CGFloat = 1.0 // Points
  static let grainSoftness: CGFloat = 0.5 // Gaussian blur radius in points
  static let grainContrast: Float = 1.05
  static let grainOpacity: Float = 0.04
  static let tintColor = NSColor(white: 0.96, alpha: 0.01)
}

struct Texture: Sendable {
  enum Error: Swift.Error, LocalizedError {
    case failedToRenderTexture(Metrics)

    var errorDescription: String? {
      switch self {
      case .failedToRenderTexture(let metrics): "Failed to render \(metrics) texture."
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

  let metrics: Metrics
  let image: CGImage

  @concurrent
  static func render(for metrics: Set<Metrics>) async throws -> [Metrics: Texture] {
    let context = CIContext(options: [.cacheIntermediates: false, .allowLowPower: true, .workingColorSpace: NSNull()])
    let colorSpace = CGColorSpace(name: CGColorSpace.genericGrayGamma2_2) ?? CGColorSpaceCreateDeviceGray()

    var textures: [Metrics: Texture] = [:]

    for metrics in metrics {
      guard let randomImage = CIFilter.randomGenerator().outputImage else {
        throw Error.failedToRenderTexture(metrics)
      }

      let pointScale = CGAffineTransform(
        scaleX: Configuration.grainSize * metrics.scaleFactor,
        y: Configuration.grainSize * metrics.scaleFactor
      )

      let blurFilter = CIFilter.gaussianBlur()
      blurFilter.inputImage = randomImage.settingAlphaOne(in: .infinite).transformed(by: pointScale)
      blurFilter.radius = Float(Configuration.grainSoftness * metrics.scaleFactor)

      let contrastFilter = CIFilter.colorControls()
      contrastFilter.inputImage = blurFilter.outputImage
      contrastFilter.contrast = Configuration.grainContrast
      contrastFilter.saturation = 0

      guard
        let textureImage = contrastFilter.outputImage,
        let image = context.createCGImage(
          textureImage,
          from: CGRect(x: 0, y: 0, width: metrics.pixelWidth, height: metrics.pixelHeight),
          format: .L8,
          colorSpace: colorSpace
        )
      else {
        throw Error.failedToRenderTexture(metrics)
      }

      textures[metrics] = Texture(metrics: metrics, image: image)
    }

    return textures
  }
}

final class TextureWindow: NSWindow {
  private(set) var texture: Texture

  private let textureLayer = CALayer()

  init(screen: NSScreen, texture: Texture) {
    self.texture = texture

    super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

    let rootLayer = CALayer()
    rootLayer.backgroundColor = Configuration.tintColor.cgColor
    rootLayer.addSublayer(textureLayer)

    let contentView = NSView()
    contentView.layer = rootLayer
    contentView.wantsLayer = true

    textureLayer.contentsGravity = .bottomLeft
    textureLayer.opacity = Configuration.grainOpacity

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
  }

  func update(screen: NSScreen, texture: Texture) {
    self.texture = texture

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    setFrame(screen.frame, display: false)
    textureLayer.frame = CGRect(origin: .zero, size: screen.frame.size)
    textureLayer.contentsScale = texture.metrics.scaleFactor
    textureLayer.contents = texture.image

    CATransaction.commit()
  }
}

@MainActor
final class TextureOverlayManager {
  private(set) var isEnabled = false

  private let startDate = Date.now
  private let screenParametersUpdateDebounceInterval: Duration = .milliseconds(250)
  private var windows: [CGDirectDisplayID: TextureWindow] = [:]
  private var screenParametersObservationTask: Task<Void, Never>?
  private var updateTask: Task<Void, Never>?

  init() {
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
      "  Display \(displayID): frame \(window.frame), texture \(window.texture.metrics), visible: \(window.isVisible)"
    }

    Log.info(
      """
      Diagnostic report:
        Started: \(startDate.formatted(.dateTime))
        Enabled: \(isEnabled)
        Update pending: \(updateTask != nil)
        Windows: \(windows.count)
      \(windowsInfo.map { "  \($0)" }.joined(separator: "\n"))
      """
    )
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
    let requiredMetrics = Set(screens.values.map(Texture.Metrics.init(screen:)))

    var textures = Dictionary(
      windows.values.map { ($0.texture.metrics, $0.texture) },
      uniquingKeysWith: { first, _ in first }
    ).filter { requiredMetrics.contains($0.key) }

    let missingMetrics = requiredMetrics.subtracting(textures.keys)

    if !missingMetrics.isEmpty {
      do {
        textures.merge(try await Texture.render(for: missingMetrics)) { _, new in new }
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
      guard let texture = textures[Texture.Metrics(screen: screen)] else {
        continue
      }

      if let window = windows[displayID] {
        window.update(screen: screen, texture: texture)
      } else {
        let window = TextureWindow(screen: screen, texture: texture)
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
enum PaperGrain {
  static func main() {
    Agent.run(subsystem: Configuration.subsystem, activationPolicy: .accessory) {
      AppDelegate()
    }
  }
}
