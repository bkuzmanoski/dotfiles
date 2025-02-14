#!/usr/bin/swift

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

func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
  let newImage = NSImage(size: size)
  newImage.lockFocus()
  image.draw(
    in: NSRect(origin: .zero, size: size),
    from: NSRect(origin: .zero, size: image.size),
    operation: .sourceOver,
    fraction: 1.0)
  newImage.unlockFocus()
  return newImage
}

func getIcon(forApp name: String) -> NSImage? {
  let workspace = NSWorkspace.shared
  let runningApps = workspace.runningApplications
  if let runningApp = runningApps.first(where: { $0.localizedName == name }),
    let bundleId = runningApp.bundleIdentifier,
    let url = workspace.urlForApplication(withBundleIdentifier: bundleId)
  {
    return workspace.icon(forFile: url.path)
  }
  // Fallback to generic executable icon
  let genericIconPath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ExecutableBinaryIcon.icns"
  return NSImage(contentsOfFile: genericIconPath)
}

func writePNGData(from image: NSImage, to outputPath: String) throws {
  let resizedIcon = resizeImage(image, to: NSSize(width: 22, height: 22))
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
    print("Usage: \(scriptName) \"Application Name\"")
    exit(1)
  }

  let appName = CommandLine.arguments[1]
  let fileManager = FileManager.default
  let cachePath = NSString(string: "~/.cache/sketchybar/app-icons").expandingTildeInPath

  // Ensure the cache directory exists
  do {
    try ensureCacheDirectory(at: cachePath)
  } catch {
    print("Error creating cache directory at \(cachePath): \(error)")
    exit(1)
  }

  let outputPath = (cachePath as NSString).appendingPathComponent("\(appName).png")

  // If cached file exists, use it
  if fileManager.fileExists(atPath: outputPath) {
    print(outputPath)
    exit(0)
  }

  // Generate the icon
  guard let icon = getIcon(forApp: appName) else {
    print("Failed to find icon for \(appName)")
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
