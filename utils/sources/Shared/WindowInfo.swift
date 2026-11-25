import AppKit

struct WindowInfo {
  let id: CGWindowID
  let level: CGWindowLevel
  let ownerProcessIdentifier: pid_t
  let ownerName: String?
  let title: String?
  let alpha: Double
  let bounds: CGRect

  var ownerBundleIdentifier: String? {
    NSRunningApplication(processIdentifier: ownerProcessIdentifier)?.bundleIdentifier
  }

  static func list(options: CGWindowListOption, relativeTo windowID: CGWindowID = kCGNullWindowID) -> [WindowInfo]? {
    return (CGWindowListCopyWindowInfo(options, windowID) as? [[String: Any]])?.compactMap(WindowInfo.init)
  }

  private init?(_ windowInfo: [String: Any]) {
    guard
      let id = windowInfo[kCGWindowNumber as String] as? CGWindowID,
      let level = windowInfo[kCGWindowLayer as String] as? CGWindowLevel,
      let ownerProcessIdentifier = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
      let alpha = windowInfo[kCGWindowAlpha as String] as? Double,
      let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
      let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
    else {
      return nil
    }

    self.id = id
    self.level = level
    self.ownerProcessIdentifier = ownerProcessIdentifier
    self.ownerName = windowInfo[kCGWindowOwnerName as String] as? String
    self.title = windowInfo[kCGWindowName as String] as? String
    self.alpha = alpha
    self.bounds = bounds
  }
}
