// Shared: WindowInfo

import AppKit

enum WindowManagerOverlay {
  case missionControl
  case appExpose
  case showDesktop

  private static let bundleIdentifier = "com.apple.WindowManager"
  private static let spacesBarWindowLevel: CGWindowLevel = 14
  private static let showDesktopWindowLevel: CGWindowLevel = 18
  private static let exposeShieldWindowLevel: CGWindowLevel = 19
  private static let overlayWindowLevels: Set<CGWindowLevel> = [showDesktopWindowLevel, exposeShieldWindowLevel]

  static var onScreen: WindowManagerOverlay? {
    let windowLevels = Set(
      (WindowInfo.list(options: [.optionOnScreenOnly, .excludeDesktopElements]) ?? [])
        .filter { windowInfo in
          (windowInfo.level == spacesBarWindowLevel || overlayWindowLevels.contains(windowInfo.level))
            && windowInfo.ownerBundleIdentifier == bundleIdentifier
        }
        .map(\.level)
    )

    if windowLevels.contains(exposeShieldWindowLevel) {
      return windowLevels.contains(spacesBarWindowLevel) ? .missionControl : .appExpose
    }

    return windowLevels.contains(showDesktopWindowLevel) ? .showDesktop : nil
  }

  static func isOverlayWindow(_ windowInfo: WindowInfo) -> Bool {
    return overlayWindowLevels.contains(windowInfo.level) && windowInfo.ownerBundleIdentifier == bundleIdentifier
  }
}
