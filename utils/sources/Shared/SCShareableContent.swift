import ScreenCaptureKit

extension SCShareableContent {
  enum Error: Swift.Error, LocalizedError {
    case displayNotFound(CGDirectDisplayID)

    var errorDescription: String? {
      switch self {
      case .displayNotFound(let displayID): "Display \(displayID) not found in shareable content."
      }
    }
  }

  func contentFilter(
    forDisplay displayID: CGDirectDisplayID,
    excludingBundleIdentifiers bundleIdentifiers: Set<String> = []
  ) throws -> SCContentFilter {
    guard let display = displays.first(where: { $0.displayID == displayID }) else {
      throw Error.displayNotFound(displayID)
    }

    let currentProcessIdentifier = NSRunningApplication.current.processIdentifier

    return SCContentFilter(
      display: display,
      excludingApplications: applications.filter {
        $0.processID == currentProcessIdentifier || bundleIdentifiers.contains($0.bundleIdentifier)
      },
      exceptingWindows: []
    )
  }
}
