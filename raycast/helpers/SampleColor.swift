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
var outputFormat = OutputFormat.hex

if arguments.contains("-h") || arguments.contains("--help") {
  print("Usage: \(arguments[0]) [--rgb | --hex]")
  exit(0)
}

if arguments.count > 1, let format = OutputFormat(fromArgument: arguments[1]) {
  outputFormat = format
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

NSColorSampler().show { selectedColor in
  guard let selectedColor else {
    NSApplication.shared.terminate(nil)
    return
  }

  let pasteboard = NSPasteboard.general
  let output = selectedColor.string(for: outputFormat)
  pasteboard.clearContents()
  pasteboard.setString(output, forType: .string)
  print(output)
  NSApplication.shared.terminate(nil)
}

app.run()
