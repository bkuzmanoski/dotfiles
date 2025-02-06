#!/usr/bin/swift

import AppKit

guard CommandLine.arguments.count > 1 else {
  let scriptName = (CommandLine.arguments[0] as NSString).lastPathComponent

  print("Usage: \(scriptName) \"Application Name\"")
  exit(1)
}

let appName = CommandLine.arguments[1]

// Ensure cache directory exists
let fileManager = FileManager.default
let cacheDir = NSString(string: "~/.cache/sketchybar/app-icons").expandingTildeInPath
if !fileManager.fileExists(atPath: cacheDir) {
  try? fileManager.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
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

func workspaceIconForApp(_ app: String) -> NSImage? {
  let workspace = NSWorkspace.shared
  let runningApps = workspace.runningApplications

  // First try to find the app by name
  if let url = workspace.urlForApplication(withBundleIdentifier: app) {
    return workspace.icon(forFile: url.path)
  }

  // Fallback to searching through running applications
  if let runningApp = runningApps.first(where: { $0.localizedName == app }),
    let bundleId = runningApp.bundleIdentifier,
    let url = workspace.urlForApplication(withBundleIdentifier: bundleId)
  {
    return workspace.icon(forFile: url.path)
  }

  // Fallback to generic app icon
  return NSImage(named: NSImage.applicationIconName)
}

if let icon = workspaceIconForApp(appName) {
  // Resize the icon
  let resizedIcon = resizeImage(icon, to: NSSize(width: 22, height: 22))

  // Save the resized icon
  let outputPath = (cacheDir as NSString).appendingPathComponent("\(appName).png")

  if let pngData = resizedIcon.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: pngData),
    let pngOutput = bitmap.representation(using: .png, properties: [:])
  {
    do {
      try pngOutput.write(to: URL(fileURLWithPath: outputPath))
      print(outputPath)
      exit(0)
    } catch {
      print("Error saving icon: \(error)")
      exit(1)
    }
  } else {
    print("Error converting icon to PNG")
    exit(1)
  }
} else {
  print("Failed to find icon for \(appName)")
  exit(1)
}
