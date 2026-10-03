import AppKit

extension NSRunningApplication {
  var isSystemAgent: Bool {
    activationPolicy != .regular && bundleURL?.path(percentEncoded: false).hasPrefix("/System/") == true
  }
}
