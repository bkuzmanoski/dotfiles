// Shared: Log

// Customizes AppKit window styling through private global preferences:
// - `NSConvolutionOverride1` and `NSConvolutionOverride2` control corner radii for standard and utility titled windows.
// - `NSWindowShadowSpec` overrides the default AppKit shadow spec (`_NSWindowDefaultShadowSpec`).

import Foundation
import MachO

extension Data {
  func double(at offset: Int) -> Double {
    return withUnsafeBytes { $0.double(at: offset) }
  }

  mutating func setDouble(_ value: Double, at offset: Int) {
    withUnsafeMutableBytes { $0.storeBytes(of: value, toByteOffset: offset, as: Double.self) }
  }

  func byte(at offset: Int) -> UInt8 {
    return self[startIndex + offset]
  }

  mutating func setByte(_ value: UInt8, at offset: Int) {
    self[startIndex + offset] = value
  }
}

extension UnsafeRawBufferPointer {
  func double(at offset: Int) -> Double {
    return loadUnaligned(fromByteOffset: offset, as: Double.self)
  }
}

enum HorizontalAlignment {
  case leading
  case trailing
}

// AppKit rounds rim radii to 2 or 3 pixels when `radius * backingScaleFactor > 2`. Retina
// displays support 2 px and 3 px rims, while non-Retina displays render both as 2 px.
enum RimWidth: String, CaseIterable {
  case thin
  case thick

  var radius: Double {
    switch self {
    case .thin: 0.5
    case .thick: 1
    }
  }
}

// WindowServer supports only black and white rims.
enum RimColor: String, CaseIterable {
  case dark
  case light

  var flag: UInt8 {
    switch self {
    case .dark: 0
    case .light: 1
    }
  }

  init(flag: UInt8) {
    self = flag == 0 ? .dark : .light
  }
}

struct ShadowSpec: Equatable {
  enum Error: Swift.Error, LocalizedError {
    case appKitFrameworkNotFound
    case defaultShadowSpecDataNotFound(matchCount: Int)
    case unexpectedShadowVariantIndex(Int)

    var errorDescription: String? {
      switch self {
      case .appKitFrameworkNotFound:
        "Failed to load AppKit.framework."

      case .defaultShadowSpecDataNotFound(let matchCount):
        "Failed to uniquely identify default shadow spec data in AppKit.framework (found \(matchCount) matches)."

      case .unexpectedShadowVariantIndex(let index):
        "Shadow variant index \(index) doesn't map to a window kind and accessibility level."
      }
    }
  }

  private enum Field: Int {
    case shadowDensity = 0x00
    case shadowRadius = 0x08
    case shadowOffset = 0x10
    case hardRimStyle = 0x18
    case rimDensity = 0x20
    case rimRadius = 0x28
    case rimWhite = 0x30
    case innerRimDensity = 0x38
    case innerRimRadius = 0x40
    case innerRimWhite = 0x48

    static let densities: [Field] = [.shadowDensity, .rimDensity, .innerRimDensity]
    static let radii: [Field] = [.shadowRadius, .rimRadius, .innerRimRadius]
    static let numeric = densities + radii + [.shadowOffset]
    static let flags: [Field] = [.hardRimStyle, .rimWhite, .innerRimWhite]
  }

  /// `_NSWindowShadowVariant` in AppKit, describing the shadow style for a specific window state.
  ///
  /// Each variant's values are stored in the shadow spec data at index
  /// `accessibilityLevel * 16 + (isActive ? 0 : 8) + (isDarkAppearance ? 4 : 0) + kind` (byte offset `index * 80`).
  struct Variant {
    /// The window kind encoded in the low bits of `-[NSWindow shadowOptionsForActiveAppearance:]`.
    enum Kind: Int, CustomStringConvertible {
      case titled // Titled windows other than panels.
      case panel // Panels (including utility and HUD windows), popovers, menus, and borderless windows.
      case sheet
      case unknown

      var description: String {
        switch self {
        case .titled: "Titled"
        case .panel: "Panel"
        case .sheet: "Sheet"
        case .unknown: "Unknown"
        }
      }
    }

    enum AccessibilityLevel: Int, CaseIterable, CustomStringConvertible {
      case standard
      case increaseContrastOrButtonShapes
      case increaseContrastAndButtonShapes

      var description: String {
        switch self {
        case .standard: "Standard"
        case .increaseContrastOrButtonShapes: "Increase Contrast or Button Shapes"
        case .increaseContrastAndButtonShapes: "Increase Contrast and Button Shapes"
        }
      }
    }

    let kind: Kind
    let isDarkAppearance: Bool
    let isActive: Bool
    let accessibilityLevel: AccessibilityLevel
    let shadowDensity: Double
    let shadowRadius: Double
    let shadowOffset: Double
    let rimDensity: Double
    let rimRadius: Double
    let rimColor: RimColor
    let innerRimDensity: Double
    let innerRimRadius: Double
  }

  private static let appKitFrameworkPath = "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit"
  private static let variantCount = 48
  private static let variantSize = 80
  private static let size = variantCount * variantSize // AppKit ignores the override unless it is exactly 0xF00 bytes.

  private(set) var data: Data

  var variants: [Variant] {
    get throws {
      try variantIndices.map { index in
        guard
          let kind = Variant.Kind(rawValue: index % 4),
          let accessibilityLevel = Variant.AccessibilityLevel(rawValue: index / 16)
        else {
          throw Error.unexpectedShadowVariantIndex(index)
        }

        return Variant(
          kind: kind,
          isDarkAppearance: index / 4 % 2 == 1,
          isActive: index / 8 % 2 == 0,
          accessibilityLevel: accessibilityLevel,
          shadowDensity: value(of: .shadowDensity, inVariant: index),
          shadowRadius: value(of: .shadowRadius, inVariant: index),
          shadowOffset: value(of: .shadowOffset, inVariant: index),
          rimDensity: value(of: .rimDensity, inVariant: index),
          rimRadius: value(of: .rimRadius, inVariant: index),
          rimColor: RimColor(flag: data.byte(at: offset(of: .rimWhite, inVariant: index))),
          innerRimDensity: value(of: .innerRimDensity, inVariant: index),
          innerRimRadius: value(of: .innerRimRadius, inVariant: index)
        )
      }
    }
  }

  private var variantIndices: Range<Int> { 0..<data.count / Self.variantSize }

  init?(data: Data) {
    guard data.count == Self.size, data.withUnsafeBytes({ Self.isShadowSpecData($0) }) else {
      return nil
    }

    self.data = data
  }

  static func systemDefault() throws -> ShadowSpec {
    let header = try appKitFrameworkHeader()

    var sectionSize: UInt = 0

    guard let section = getsectiondata(header, "__TEXT", "__const", &sectionSize) else {
      throw Error.defaultShadowSpecDataNotFound(matchCount: 0)
    }

    let bytes = UnsafeRawBufferPointer(start: section, count: Int(sectionSize))
    let matches = stride(from: 0, through: bytes.count - size, by: 8).filter {
      isShadowSpecData(UnsafeRawBufferPointer(rebasing: bytes[$0..<$0 + size]))
    }

    guard
      matches.count == 1,
      let offset = matches.first,
      let shadowSpec = ShadowSpec(data: Data(bytes[offset..<offset + size]))
    else {
      throw Error.defaultShadowSpecDataNotFound(matchCount: matches.count)
    }

    return shadowSpec
  }

  func modified(
    withShadowFactor shadowFactor: Double,
    rimFactor: Double,
    rimWidth: RimWidth?,
    rimColor: RimColor?,
    innerRimFactor: Double
  ) -> ShadowSpec {
    var shadowSpec = self
    shadowSpec.scaleDensity(.shadowDensity, by: shadowFactor)
    shadowSpec.scaleDensity(.rimDensity, by: rimFactor)
    shadowSpec.scaleDensity(.innerRimDensity, by: innerRimFactor)

    if let rimWidth {
      shadowSpec.setRimWidth(rimWidth)
    }

    if let rimColor {
      shadowSpec.setRimColor(rimColor)
    }

    return shadowSpec
  }

  private mutating func scaleDensity(_ field: Field, by factor: Double) {
    for index in variantIndices {
      data.setDouble(min(value(of: field, inVariant: index) * factor, 1), at: offset(of: field, inVariant: index))
    }
  }

  private mutating func setRimWidth(_ rimWidth: RimWidth) {
    for index in variantIndices {
      data.setDouble(rimWidth.radius, at: offset(of: .rimRadius, inVariant: index))
    }
  }

  private mutating func setRimColor(_ rimColor: RimColor) {
    for index in variantIndices {
      data.setByte(rimColor.flag, at: offset(of: .rimWhite, inVariant: index))
    }
  }

  private static func appKitFrameworkHeader() throws -> UnsafePointer<mach_header_64> {
    guard dlopen(appKitFrameworkPath, RTLD_LAZY) != nil else {
      throw Error.appKitFrameworkNotFound
    }

    for index in 0..<_dyld_image_count() {
      guard
        let imageName = _dyld_get_image_name(index),
        String(cString: imageName) == appKitFrameworkPath,
        let header = _dyld_get_image_header(index)
      else {
        continue
      }

      return UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
    }

    throw Error.appKitFrameworkNotFound
  }

  private static func isShadowSpecData(_ bytes: UnsafeRawBufferPointer) -> Bool {
    return stride(from: 0, to: bytes.count, by: variantSize).allSatisfy { isVariant(in: bytes, at: $0) }
  }

  private static func isVariant(in bytes: UnsafeRawBufferPointer, at variant: Int) -> Bool {
    return Field.numeric.allSatisfy { (0...100).contains(bytes.double(at: variant + $0.rawValue)) }
      && Field.densities.allSatisfy { bytes.double(at: variant + $0.rawValue) <= 1 }
      && Field.radii.allSatisfy { bytes.double(at: variant + $0.rawValue) != 0 }
      && Field.flags.allSatisfy { isFlag(in: bytes, at: variant + $0.rawValue) }
  }

  private static func isFlag(in bytes: UnsafeRawBufferPointer, at offset: Int) -> Bool {
    // Stored as 8-byte fields holding 0 or 1.
    return bytes[offset] <= 1 && bytes[offset + 1..<offset + 8].allSatisfy { $0 == 0 }
  }

  private func value(of field: Field, inVariant index: Int) -> Double {
    return data.double(at: offset(of: field, inVariant: index))
  }

  private func offset(of field: Field, inVariant index: Int) -> Int {
    return index * Self.variantSize + field.rawValue
  }
}

enum Command: String, CaseIterable {
  case apply
  case `dry-run`
  case status
  case reset
}

struct Options {
  private static let usageDescription = """
    Usage:
      \(ProcessInfo.processInfo.processName) <command> [options]

    Commands:
      apply    Write the style to the global domain (omitted options will be reset to the system default)
      dry-run  Print the resulting style without writing it
      status   Print the currently applied style
      reset    Reset the style to the system default

    Relaunch apps after applying or resetting overrides.

    Options (apply, dry-run):
      -c, --corner-radius <pt>          Set the standard window corner radius [default: system default]
      -u, --utility-corner-radius <pt>  Set the utility window corner radius [default: --corner-radius]
      -r, --rim <factor>                Scale the outer rim opacity [default: 1]
      -w, --rim-width <width>           Set the outer rim width (\(RimWidth.allCases.map(\.rawValue).joined(separator: ", "))) [default: system default]
      -k, --rim-color <color>           Set the outer rim color (\(RimColor.allCases.map(\.rawValue).joined(separator: ", "))) [default: system default]
      -i, --inner-rim <factor>          Scale the inner rim opacity [default: 1]
      -s, --shadow <factor>             Scale the shadow opacity [default: 1]
      -h, --help                        Show this help message
    """

  var command: Command
  var cornerRadius: Double?
  var utilityWindowCornerRadius: Double?
  var rimFactor = 1.0
  var rimWidth: RimWidth?
  var rimColor: RimColor?
  var innerRimFactor = 1.0
  var shadowFactor = 1.0

  var effectiveUtilityWindowCornerRadius: Double? { utilityWindowCornerRadius ?? cornerRadius }

  init(arguments: some Sequence<String>) {
    var arguments = arguments.makeIterator()
    var positionalArguments: [String] = []
    var optionArguments: [String] = []

    while let argument = arguments.next() {
      if argument.hasPrefix("-") {
        optionArguments.append(argument)
      }

      switch argument {
      case "-c", "--corner-radius":
        self.cornerRadius = Self.number(from: arguments.next(), for: argument)

      case "-u", "--utility-corner-radius":
        self.utilityWindowCornerRadius = Self.number(from: arguments.next(), for: argument)

      case "-r", "--rim":
        self.rimFactor = Self.number(from: arguments.next(), for: argument)

      case "-w", "--rim-width":
        self.rimWidth = Self.choice(from: arguments.next(), for: argument)

      case "-k", "--rim-color":
        self.rimColor = Self.choice(from: arguments.next(), for: argument)

      case "-i", "--inner-rim":
        self.innerRimFactor = Self.number(from: arguments.next(), for: argument)

      case "-s", "--shadow":
        self.shadowFactor = Self.number(from: arguments.next(), for: argument)

      case "-h", "--help":
        print(Self.usageDescription)
        exit(EXIT_SUCCESS)

      default:
        guard !argument.hasPrefix("-") else {
          Self.printUsageErrorAndExit("Unknown argument: \(argument)")
        }

        positionalArguments.append(argument)
      }
    }

    guard
      positionalArguments.count == 1,
      let command = Self.choice(Command.self, matching: positionalArguments[0])
    else {
      Self.printUsageErrorAndExit(
        "Expected one command: \(Command.allCases.map(\.rawValue).joined(separator: ", "))."
      )
    }

    if [.status, .reset].contains(command), let option = optionArguments.first {
      Self.printUsageErrorAndExit("\(command.rawValue) takes no options (got '\(option)').")
    }

    self.command = command
  }

  private static func number(from value: String?, for argument: String) -> Double {
    guard let value else {
      printUsageErrorAndExit("Missing value for '\(argument)'.")
    }

    guard let number = Double(value), number.isFinite, number >= 0 else {
      printUsageErrorAndExit("Invalid value for '\(argument)': \(value). Expected a non-negative number.")
    }

    return number
  }

  private static func choice<Choice: RawRepresentable<String> & CaseIterable>(
    from value: String?,
    for argument: String
  ) -> Choice {
    guard let value, let choice = choice(Choice.self, matching: value) else {
      printUsageErrorAndExit(
        "Invalid value for '\(argument)'. Expected one of: \(Choice.allCases.map(\.rawValue).joined(separator: ", "))."
      )
    }

    return choice
  }

  private static func choice<Choice: RawRepresentable<String> & CaseIterable>(
    _ type: Choice.Type,
    matching value: String
  ) -> Choice? {
    return Choice.allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }
  }

  private static func printUsageErrorAndExit(_ message: String) -> Never {
    Log.error("Error: \(message)\n\n\(usageDescription)")
    exit(EX_USAGE)
  }
}

@main
enum WindowStyle {
  private static let cornerRadiusKey = "NSConvolutionOverride1"
  private static let utilityCornerRadiusKey = "NSConvolutionOverride2"
  private static let shadowSpecKey = "NSWindowShadowSpec"

  static func main() {
    let options = Options(arguments: CommandLine.arguments.dropFirst())

    do {
      switch options.command {
      case .apply: try apply(options)
      case .`dry-run`: try printStyle(options)
      case .status: try printStatus()
      case .reset: reset()
      }
    } catch {
      Log.error("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }

  private static func apply(_ options: Options) throws {
    let systemDefaultShadowSpec = try ShadowSpec.systemDefault()
    let modifiedShadowSpec = systemDefaultShadowSpec.modified(
      withShadowFactor: options.shadowFactor,
      rimFactor: options.rimFactor,
      rimWidth: options.rimWidth,
      rimColor: options.rimColor,
      innerRimFactor: options.innerRimFactor
    )

    writePreference(
      modifiedShadowSpec == systemDefaultShadowSpec ? nil : modifiedShadowSpec.data as CFData,
      for: shadowSpecKey
    )
    writePreference(options.cornerRadius.map { cornerRadiusPreference($0) as CFNumber }, for: cornerRadiusKey)
    writePreference(
      options.effectiveUtilityWindowCornerRadius.map { cornerRadiusPreference($0) as CFNumber },
      for: utilityCornerRadiusKey
    )
    synchronizePreferences()
  }

  private static func reset() {
    writePreference(nil, for: shadowSpecKey)
    writePreference(nil, for: cornerRadiusKey)
    writePreference(nil, for: utilityCornerRadiusKey)
    synchronizePreferences()
  }

  private static func printStyle(_ options: Options) throws {
    try printStyle(
      cornerRadius: options.cornerRadius.map { Double(cornerRadiusPreference($0)) },
      utilityCornerRadius: options.effectiveUtilityWindowCornerRadius.map { Double(cornerRadiusPreference($0)) },
      shadowSpec: try ShadowSpec.systemDefault().modified(
        withShadowFactor: options.shadowFactor,
        rimFactor: options.rimFactor,
        rimWidth: options.rimWidth,
        rimColor: options.rimColor,
        innerRimFactor: options.innerRimFactor
      )
    )
  }

  private static func printStatus() throws {
    let shadowSpec: ShadowSpec

    if let data = readPreference(shadowSpecKey) as? Data {
      guard let appliedShadowSpec = ShadowSpec(data: data) else {
        Log.error("Error: \(shadowSpecKey) is set but isn't valid shadow spec data (\(data.count) bytes).")
        exit(EXIT_FAILURE)
      }

      shadowSpec = appliedShadowSpec
    } else {
      shadowSpec = try ShadowSpec.systemDefault()
    }

    try printStyle(
      cornerRadius: (readPreference(cornerRadiusKey) as? NSNumber)?.doubleValue,
      utilityCornerRadius: (readPreference(utilityCornerRadiusKey) as? NSNumber)?.doubleValue,
      shadowSpec: shadowSpec
    )
  }

  private static func printStyle(cornerRadius: Double?, utilityCornerRadius: Double?, shadowSpec: ShadowSpec) throws {
    let cornerRadius = cornerRadiusDescription(cornerRadius)
    let utilityCornerRadius = cornerRadiusDescription(utilityCornerRadius)
    let variants = try shadowSpec.variants

    print(
      """
      Corner radius: \(cornerRadius) (standard), \(utilityCornerRadius) (utility)

      ————————————————— Variant ————————————————  ——————— Shadow ——————  ————————— Rim ————————  —— Inner Rim ——
      \u{1B}[1mKIND     APPEARANCE  STATE     A11Y LEVEL*  OPACITY  RADIUS     Y  OPACITY  RADIUS  COLOR  OPACITY  RADIUS\u{1B}[0m
      \(
        variants.map { variant in
          let kind = outputColumn(variant.kind.description, width: 7, alignment: .leading)
          let appearance = outputColumn(variant.isDarkAppearance ? "Dark" : "Light", width: 10, alignment: .leading)
          let state = outputColumn(variant.isActive ? "Active" : "Inactive", width: 8, alignment: .leading)
          let accessibilityLevel = outputColumn(String(variant.accessibilityLevel.rawValue), width: 11, alignment: .trailing)
          let shadowDensity = outputColumn(variant.shadowDensity, width: 7, fractionLength: 3)
          let shadowRadius = outputColumn(variant.shadowRadius, width: 6, fractionLength: 1)
          let shadowOffset = outputColumn(variant.shadowOffset, width: 4, fractionLength: 1)
          let rimDensity = outputColumn(variant.rimDensity, width: 7, fractionLength: 3)
          let rimRadius = outputColumn(variant.rimRadius, width: 6, fractionLength: 2)
          let rimColor = outputColumn(variant.rimColor.rawValue.capitalized, width: 5, alignment: .leading)
          let innerRimDensity = outputColumn(variant.innerRimDensity, width: 7, fractionLength: 3)
          let innerRimRadius = outputColumn(variant.innerRimRadius, width: 6, fractionLength: 2)

          return "\(kind)  \(appearance)  \(state)  \(accessibilityLevel)  "
            + "\(shadowDensity)  \(shadowRadius)  \(shadowOffset)  "
            + "\(rimDensity)  \(rimRadius)  \(rimColor)  "
            + "\(innerRimDensity)  \(innerRimRadius)"
        }.joined(separator: "\n")
      )

      *A11y Level: \(ShadowSpec.Variant.AccessibilityLevel.allCases.map { "\($0.rawValue) = \($0.description)" }.joined(separator: ", "))
      """
    )
  }

  private static func outputColumn(_ value: Double, width: Int, fractionLength: Int) -> String {
    return outputColumn(value.formatted(.number.precision(.fractionLength(fractionLength))), width: width)
  }

  private static func outputColumn(
    _ text: String,
    width: Int,
    alignment: HorizontalAlignment = .trailing
  ) -> String {
    let padding = String(repeating: " ", count: max(width - text.count, 0))

    switch alignment {
    case .leading: return text + padding
    case .trailing: return padding + text
    }
  }

  private static func cornerRadiusPreference(_ radius: Double) -> Float {
    return max(Float(radius), .leastNonzeroMagnitude) // AppKit treats `0` as unset.
  }

  private static func cornerRadiusDescription(_ radius: Double?) -> String {
    return radius.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) pt" } ?? "system default"
  }

  private static func readPreference(_ key: String) -> CFPropertyList? {
    return CFPreferencesCopyValue(
      key as CFString,
      kCFPreferencesAnyApplication,
      kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost
    )
  }

  private static func writePreference(_ value: CFPropertyList?, for key: String) {
    CFPreferencesSetValue(
      key as CFString,
      value,
      kCFPreferencesAnyApplication,
      kCFPreferencesCurrentUser,
      kCFPreferencesAnyHost
    )
  }

  private static func synchronizePreferences() {
    guard
      CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    else {
      Log.error("Error: Failed to write to the global domain.")
      exit(EXIT_FAILURE)
    }
  }
}
