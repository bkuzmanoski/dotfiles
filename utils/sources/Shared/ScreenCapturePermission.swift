import CoreGraphics
import Foundation

enum ScreenCapturePermission {
  enum Error: Swift.Error, LocalizedError {
    case notGranted

    var errorDescription: String? {
      switch self {
      case .notGranted: "Screen capture permission not granted."
      }
    }
  }

  static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

  static func ensureGranted() throws {
    guard isGranted else {
      throw Error.notGranted
    }
  }
}
