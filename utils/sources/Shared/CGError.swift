import CoreGraphics
import Foundation

extension CGError: @retroactive _BridgedNSError, @retroactive LocalizedError {
  public var errorDescription: String? {
    let message: String

    switch self {
    case .success: message = "Success"
    case .failure: message = "Failure"
    case .illegalArgument: message = "Illegal argument"
    case .invalidConnection: message = "Invalid connection"
    case .invalidContext: message = "Invalid context"
    case .cannotComplete: message = "Cannot complete"
    case .notImplemented: message = "Not implemented"
    case .rangeCheck: message = "Range check error"
    case .typeCheck: message = "Type check error"
    case .invalidOperation: message = "Invalid operation"
    case .noneAvailable: message = "Error code not available"
    @unknown default: message = "Unknown error"
    }

    return "CGError: \(message) (\(self.rawValue))"
  }
}
