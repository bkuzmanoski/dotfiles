import AppKit

enum OutputFormat {
  case hex
  case rgb

  init?(fromArgument: String) {
    switch fromArgument.lowercased() {
    case "--hex": self = .hex
    case "--rgb": self = .rgb
    default: return nil
    }
  }
}

extension NSColor {
  func string(for format: OutputFormat) -> String {
    let color = usingColorSpace(.sRGB) ?? .black
    let red = Int((color.redComponent * 255).rounded())
    let green = Int((color.greenComponent * 255).rounded())
    let blue = Int((color.blueComponent * 255).rounded())

    switch format {
    case .hex: return String(format: "#%02x%02x%02x", red, green, blue)
    case .rgb: return "rgb(\(red), \(green), \(blue))"
    }
  }
}

let arguments = CommandLine.arguments
let programName = (arguments.first as NSString?)?.lastPathComponent ?? "SampleColor"

if arguments.contains("-h") || arguments.contains("--help") {
  print("Usage: \(programName) [--rgb|--hex]")
  exit(EXIT_SUCCESS)
}

var outputFormat: OutputFormat

if arguments.count > 1, let format = OutputFormat(fromArgument: arguments[1]) {
  outputFormat = format
} else {
  outputFormat = .hex
}

NSColorSampler().show { selectedColor in
  if let selectedColor {

    let output = selectedColor.string(for: outputFormat)

    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(output, forType: .string)

    print(output)
  }

  NSApplication.shared.terminate(nil)
}

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.run()
