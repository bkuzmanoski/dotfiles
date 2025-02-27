import AppKit

enum GetAppIconError: Error {
  case conversionError
  case savingError(Error)
}

func ensureCacheDirectory(at path: String) throws {
  let fileManager = FileManager.default
  if !fileManager.fileExists(atPath: path) {
    try fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
  }
}

func getIcon(for bundleId: String) -> NSImage? {
  let workspace = NSWorkspace.shared
  if let url = workspace.urlForApplication(withBundleIdentifier: bundleId) {
    return workspace.icon(forFile: url.path)
  }

  // Fallback to generic executable icon
  let genericIconPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ExecutableBinaryIcon.icns"
  return NSImage(contentsOfFile: genericIconPath)
}

func addShadow(to image: NSImage) -> NSImage {
  let resultImage = NSImage(size: image.size)
  resultImage.lockFocus()
  NSColor.clear.set()
  NSRect(origin: .zero, size: image.size).fill()

  if let context = NSGraphicsContext.current?.cgContext {
    let blurRadius: CGFloat = 1.0
    let offset = NSSize(width: 0, height: -1)
    context.setShadow(
      offset: CGSize(width: offset.width, height: offset.height),
      blur: blurRadius,
      color: NSColor.black.withAlphaComponent(0.25).cgColor
    )

    let insetAmount: CGFloat = 1.0
    let drawRect = NSRect(
      x: insetAmount,
      y: insetAmount,
      width: image.size.width,
      height: image.size.height
    )
    image.draw(in: drawRect)
  }

  resultImage.unlockFocus()
  return resultImage
}

func resize(_ image: NSImage, to size: NSSize) -> NSImage {
  let resizedImage = NSImage(size: size)
  resizedImage.lockFocus()
  image.draw(
    in: NSRect(origin: .zero, size: size),
    from: NSRect(origin: .zero, size: image.size),
    operation: .sourceOver,
    fraction: 1.0)
  resizedImage.unlockFocus()
  return resizedImage
}

func writePNGData(from image: NSImage, to outputPath: String) throws {
  let iconWithShadow = addShadow(to: image)
  let resizedIcon = resize(iconWithShadow, to: NSSize(width: 22, height: 22))
  guard let tiffData = resizedIcon.tiffRepresentation,
    let bitmapRep = NSBitmapImageRep(data: tiffData),
    let pngData = bitmapRep.representation(using: .png, properties: [:])
  else {
    throw GetAppIconError.conversionError
  }

  do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
  } catch {
    throw GetAppIconError.savingError(error)
  }
}

func main() {
  guard CommandLine.arguments.count == 2 else {
    let scriptName = (CommandLine.arguments[0] as NSString).lastPathComponent
    print("Usage: \(scriptName) bundleId")
    exit(1)
  }

  let bundleId = CommandLine.arguments[1]
  let fileManager = FileManager.default
  let cachePath = NSString(string: "~/.cache/sketchybar/icons").expandingTildeInPath

  // Ensure the cache directory exists
  do {
    try ensureCacheDirectory(at: cachePath)
  } catch {
    print("Error creating cache directory at \(cachePath): \(error)")
    exit(1)
  }

  let outputPath = (cachePath as NSString).appendingPathComponent("\(bundleId).png")

  // If cached file exists, use it
  if fileManager.fileExists(atPath: outputPath) {
    print(outputPath)
    exit(0)
  }

  // Generate the icon
  guard let icon = getIcon(for: bundleId) else {
    print("Failed to find icon for \(bundleId)")
    exit(1)
  }

  // Write icon PNG data to cache
  do {
    try writePNGData(from: icon, to: outputPath)
  } catch GetAppIconError.conversionError {
    print("Error converting icon to PNG")
    exit(1)
  } catch GetAppIconError.savingError(let savingError) {
    print("Error saving icon: \(savingError)")
    exit(1)
  } catch {
    print("Unexpected error: \(error)")
    exit(1)
  }

  print(outputPath)
  exit(0)
}

main()
