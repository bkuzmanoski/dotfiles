import CoreGraphics

extension CGEventFlags {
  static let modifierFlagsMask: CGEventFlags = [.maskControl, .maskAlternate, .maskShift, .maskCommand]
  static let maskLeftCommand = CGEventFlags(rawValue: 0x08)
  static let maskRightCommand = CGEventFlags(rawValue: 0x10)
}
