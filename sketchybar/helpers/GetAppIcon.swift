import AppKit

enum GetAppIconError: Error {
  case conversionError
  case saveError(Error)
}

func usage() {
  let progName = (CommandLine.arguments.first as NSString?)?.lastPathComponent ?? "GetAppIcon"
  print("Usage: \(progName) <bundleId>")
}

func parseArguments() -> String {
  // Drop the executable name and validate the remaining arguments.
  let arguments = CommandLine.arguments.dropFirst()
  guard arguments.count == 1, let bundleId = arguments.first, !bundleId.isEmpty else {
    usage()
    exit(1)
  }
  return bundleId
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

func addShadow(to image: NSImage, offset: CGSize, blur: Double, color: CGColor) -> NSImage {
  let resultImage = NSImage(size: image.size)
  resultImage.lockFocus()
  if let context = NSGraphicsContext.current?.cgContext {
    context.setShadow(offset: offset, blur: blur, color: color)
  }
  image.draw(in: NSRect(origin: .zero, size: image.size))
  resultImage.unlockFocus()
  return resultImage
}

func resize(_ image: NSImage, to size: NSSize) -> NSImage {
  let resizedImage = NSImage(size: size)
  resizedImage.lockFocus()
  image.draw(in: NSRect(origin: .zero, size: size))
  resizedImage.unlockFocus()
  return resizedImage
}

func offset(_ image: NSImage, by offset: NSPoint) -> NSImage {
  let offsetImage = NSImage(size: image.size)
  offsetImage.lockFocus()
  image.draw(
    at: offset,
    from: NSRect(origin: .zero, size: image.size),
    operation: .copy,
    fraction: 1.0
  )
  offsetImage.unlockFocus()
  return offsetImage
}

func writePNGData(from image: NSImage, to outputPath: String) throws {
  let iconWithShadow = addShadow(
    to: image,
    offset: CGSize(width: 0.0, height: -1.0),
    blur: 1.5,
    color: NSColor.black.withAlphaComponent(0.25).cgColor
  )
  let resizedIcon = resize(iconWithShadow, to: NSSize(width: 23, height: 23))
  let offsetIcon = offset(resizedIcon, by: NSPoint(x: -0.5, y: 0))
  guard let tiffData = offsetIcon.tiffRepresentation,
    let bitmapRep = NSBitmapImageRep(data: tiffData),
    let pngData = bitmapRep.representation(using: .png, properties: [:])
  else {
    throw GetAppIconError.conversionError
  }

  do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
  } catch {
    throw GetAppIconError.saveError(error)
  }
}

func main() {
  let bundleId = parseArguments()
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
    print("Error converting icon to PNG.")
    exit(1)
  } catch GetAppIconError.saveError(let saveError) {
    print("Error saving icon: \(saveError)")
    exit(1)
  } catch {
    print("Unexpected error: \(error)")
    exit(1)
  }

  print(outputPath)
  exit(0)
}

main()
