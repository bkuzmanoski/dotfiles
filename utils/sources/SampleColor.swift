// Shared: Log

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

extension Comparable {
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

struct CommandLineOptions {
  enum Error: Swift.Error {
    case helpRequested
    case invalidUsage(String)
  }

  static let usageDescription = """
    Usage:
      \(ProcessInfo.processInfo.processName) [options]

    Options:
      -f, --format <format>      Output format: 'hex' (default) or 'rgb'
      -c, --color-space <space>  Color space: 'srgb' (default) or 'native'
      -h, --help                 Show this help message
    """

  private(set) var format: RGBFormatStyle = .hex
  private(set) var colorSpace: NSColorSpace? = .sRGB

  init(arguments: some Sequence<String>) throws(Error) {
    var arguments = arguments.makeIterator()

    while let argument = arguments.next() {
      switch argument.lowercased() {
      case "-f", "--format":
        switch arguments.next()?.lowercased() {
        case "hex": self.format = .hex
        case "rgb": self.format = .rgb
        case .some(let value): throw .invalidUsage("Invalid format '\(value)'. Expected 'hex' or 'rgb'.")
        case .none: throw .invalidUsage("Missing value for '\(argument)'.")
        }

      case "-c", "--color-space":
        switch arguments.next()?.lowercased() {
        case "srgb": self.colorSpace = .sRGB
        case "native": self.colorSpace = nil
        case .some(let value): throw .invalidUsage("Invalid color space '\(value)'. Expected 'srgb' or 'native'.")
        case .none: throw .invalidUsage("Missing value for '\(argument)'.")
        }

      case "-h", "--help":
        throw .helpRequested

      default:
        throw .invalidUsage("Unknown argument: \(argument)")
      }
    }
  }
}

@main
enum SampleColor {
  static func main() {
    let options: CommandLineOptions

    do {
      options = try CommandLineOptions(arguments: CommandLine.arguments.dropFirst())
    } catch {
      switch error {
      case .helpRequested:
        print(CommandLineOptions.usageDescription)
        return

      case .invalidUsage(let message):
        Log.error("Error: \(message)\n\n\(CommandLineOptions.usageDescription)")
        exit(EX_USAGE)
      }
    }

    NSColorSampler().show { [outputFormat = options.format, outputColorSpace = options.colorSpace] color in
      MainActor.assumeIsolated {
        if let color {
          guard let color = outputColorSpace.map({ color.usingColorSpace($0) }) ?? color else {
            Log.error("Failed to convert color to the specified color space.")
            exit(EXIT_FAILURE)
          }

          let result = color.formatted(outputFormat)

          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(result, forType: .string)

          print(result)
        }

        NSApplication.shared.terminate(nil)
      }
    }

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    application.run()
  }
}
