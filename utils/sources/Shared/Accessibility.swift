import AppKit

// swift-format-ignore: NoLeadingUnderscores
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AccessibilityPermission {
  enum Error: Swift.Error, LocalizedError {
    case notGranted

    var errorDescription: String? {
      switch self {
      case .notGranted: "Accessibility permission not granted."
      }
    }
  }

  static var isGranted: Bool { AXIsProcessTrustedWithOptions(nil) }

  static func ensureGranted() throws {
    guard isGranted else {
      throw Error.notGranted
    }
  }
}

extension AXUIElement {
  enum Error: Swift.Error, LocalizedError {
    case typeMismatch

    var errorDescription: String? {
      switch self {
      case .typeMismatch: "Returned value type does not match expected type."
      }
    }
  }

  static func setGlobalMessagingTimeout(seconds timeoutInSeconds: Float) {
    AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), timeoutInSeconds)
  }

  static func focusedApplicationBundleIdentifier() throws -> String? {
    var rawValue: CFTypeRef?

    try AXUIElementCopyAttributeValue(
      AXUIElementCreateSystemWide(),
      kAXFocusedApplicationAttribute as CFString,
      &rawValue
    ).throwIfFailed()

    guard let rawValue, CFGetTypeID(rawValue) == AXUIElementGetTypeID() else {
      throw Error.typeMismatch
    }

    var processIdentifier: pid_t = -1

    try AXUIElementGetPid(rawValue as! AXUIElement, &processIdentifier).throwIfFailed()

    guard processIdentifier > 0 else {
      return nil
    }

    return NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
  }

  static func element(for pid: pid_t) -> AXUIElement {
    return AXUIElementCreateApplication(pid)
  }

  func windowID() throws -> CGWindowID {
    var windowID: CGWindowID = kCGNullWindowID

    try _AXUIElementGetWindow(self, &windowID).throwIfFailed()

    return windowID
  }

  func children() throws -> [AXUIElement] {
    var valuesRef: CFArray?

    try AXUIElementCopyAttributeValues(
      self,
      NSAccessibility.Attribute.children.rawValue as CFString,
      0,
      Int.max,
      &valuesRef
    ).throwIfFailed()

    return valuesRef as? [AXUIElement] ?? []
  }

  func value<T>(for attribute: NSAccessibility.Attribute, as type: T.Type = T.self) throws -> T {
    var rawValue: CFTypeRef?

    try AXUIElementCopyAttributeValue(self, attribute.rawValue as CFString, &rawValue).throwIfFailed()

    guard let value = rawValue as? T else {
      throw Error.typeMismatch
    }

    return value
  }

  func values(for attributes: [NSAccessibility.Attribute]) throws -> [NSAccessibility.Attribute: Any]? {
    var rawValues: CFArray?

    try AXUIElementCopyMultipleAttributeValues(
      self,
      attributes.map { $0.rawValue as CFString } as CFArray,
      AXCopyMultipleAttributeOptions(rawValue: 0),
      &rawValues
    ).throwIfFailed()

    return (rawValues as? [AnyObject]).map { Dictionary(uniqueKeysWithValues: zip(attributes, $0)) }
  }

  func performAction(_ action: NSAccessibility.Action) throws {
    try AXUIElementPerformAction(self, action.rawValue as CFString).throwIfFailed()
  }
}

extension AXError: @retroactive _BridgedNSError, @retroactive Error, @retroactive LocalizedError {
  public var errorDescription: String? {
    let message: String

    switch self {
    case .success: message = "Success"
    case .failure: message = "Failure"
    case .illegalArgument: message = "Illegal argument"
    case .invalidUIElement: message = "Invalid UI element"
    case .invalidUIElementObserver: message = "Invalid UI element observer"
    case .cannotComplete: message = "Cannot complete"
    case .attributeUnsupported: message = "Attribute unsupported"
    case .actionUnsupported: message = "Action unsupported"
    case .notificationUnsupported: message = "Notification unsupported"
    case .notImplemented: message = "Not implemented"
    case .notificationAlreadyRegistered: message = "Notification already registered"
    case .notificationNotRegistered: message = "Notification not registered"
    case .apiDisabled: message = "API disabled"
    case .noValue: message = "No value"
    case .parameterizedAttributeUnsupported: message = "Parameterized attribute unsupported"
    case .notEnoughPrecision: message = "Not enough precision"
    @unknown default: message = "Unknown error"
    }

    return "AXError: \(message) (\(self.rawValue))"
  }

  func throwIfFailed() throws {
    if self != .success {
      throw self
    }
  }
}
