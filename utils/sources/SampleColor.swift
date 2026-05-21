import AppKit

struct HexIntegerFormatStyle<Value: BinaryInteger>: FormatStyle {
  typealias FormatInput = Value
  typealias FormatOutput = String

  var padToLength: Int
  var uppercase: Bool

  func format(_ value: Value) -> String {
    let string = String(value, radix: 16, uppercase: uppercase)
    return String(repeating: "0", count: max(0, padToLength - string.count)) + string
  }
}

extension HexIntegerFormatStyle {
  static func hex(padTo length: Int = 2, uppercase: Bool = false) -> HexIntegerFormatStyle {
    return HexIntegerFormatStyle(padToLength: length, uppercase: uppercase)
  }
}

extension BinaryInteger {
  func formatted(_ style: HexIntegerFormatStyle<Self>) -> String {
    return style.format(self)
  }
}

private extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    return min(max(self, range.lowerBound), range.upperBound)
  }
}

struct RGBFormatStyle: FormatStyle {
  static let hex = RGBFormatStyle(.hex)
  static let rgb = RGBFormatStyle(.rgb)

  typealias FormatInput = NSColor
  typealias FormatOutput = String

  enum Representation: Hashable, Codable {
    case hex
    case rgb
  }

  var representation: Representation

  init(_ representation: Representation) {
    self.representation = representation
  }

  func format(_ value: NSColor) -> String {
    let red = Self.byte(value.redComponent)
    let green = Self.byte(value.greenComponent)
    let blue = Self.byte(value.blueComponent)

    switch representation {
    case .hex: return "#\(red.formatted(.hex()))\(green.formatted(.hex()))\(blue.formatted(.hex()))"
    case .rgb: return "rgb(\(red), \(green), \(blue))"
    }
  }

  private static func byte(_ component: CGFloat) -> UInt8 {
    return UInt8(Int((component * 255).rounded()).clamped(to: 0...255))
  }
}

extension NSColor {
  func formatted<S: FormatStyle>(_ style: S) -> S.FormatOutput where S.FormatInput == NSColor {
    return style.format(self)
  }
}

func printUsageErrorAndExit(_ message: String) -> Never {
  FileHandle.standardError.write(Data("\(message)\n\n\(usageDescription)\n".utf8))
  exit(EX_USAGE)
}

let usageDescription = """
  Usage:
    \(ProcessInfo.processInfo.processName) [options]

  Options:
    -f, --format <format>      Output format: 'hex' (default) or 'rgb'
    -c, --color-space <space>  Color space: 'srgb' (default) or 'native'
    -h, --help                 Show this help message
  """

var outputFormat: RGBFormatStyle = .hex
var outputColorSpace: NSColorSpace? = .sRGB
var arguments = CommandLine.arguments.dropFirst().makeIterator()

while let argument = arguments.next() {
  switch argument.lowercased() {
  case "-f", "--format":
    switch arguments.next()?.lowercased() {
    case "hex": outputFormat = .hex
    case "rgb": outputFormat = .rgb
    case .some(let value): printUsageErrorAndExit("Invalid format '\(value)'. Expected 'hex' or 'rgb'.")
    case .none: printUsageErrorAndExit("Missing value for '\(argument)'.")
    }

  case "-c", "--color-space":
    switch arguments.next()?.lowercased() {
    case "srgb": outputColorSpace = .sRGB
    case "native": outputColorSpace = nil
    case .some(let value): printUsageErrorAndExit("Invalid color space '\(value)'. Expected 'srgb' or 'native'.")
    case .none: printUsageErrorAndExit("Missing value for '\(argument)'.")
    }

  case "-h", "--help":
    print(usageDescription)
    exit(EXIT_SUCCESS)

  default:
    printUsageErrorAndExit("Unknown argument: \(argument)")
  }
}

NSColorSampler().show { color in
  if let color {
    guard let color = outputColorSpace.map({ color.usingColorSpace($0) }) ?? color else {
      FileHandle.standardError.write(Data("Failed to convert color to the specified color space.\n".utf8))
      exit(EXIT_FAILURE)
    }

    let result = color.formatted(outputFormat)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(result, forType: .string)

    print(result)
  }

  NSApplication.shared.terminate(nil)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
