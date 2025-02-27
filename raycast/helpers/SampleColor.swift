// Tweaked version of the original script by Jesse Claven (https://github.com/jesse-c)
// https://github.com/raycast/script-commands/blob/master/commands/system/sample-color.swift

import AppKit

extension NSColor {
  var hexAlphaString: String {
    let r = lroundf(Float(redComponent) * 0xFF)
    let g = lroundf(Float(greenComponent) * 0xFF)
    let b = lroundf(Float(blueComponent) * 0xFF)
    return String(format: "#%02lx%02lx%02lx", r, g, b)
  }
}

func copyToPasteboard(_ color: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.writeObjects([color as NSPasteboardWriting])
}

let sampler = NSColorSampler()

sampler.show { selectedColor in
  if let selectedColor = selectedColor {
    let hexTuple = selectedColor.hexAlphaString
    copyToPasteboard(hexTuple)
    print("Sampled color: \(hexTuple)")
    exit(0)
  } else {
    print("Sampled color: none")
    exit(0)
  }
}

RunLoop.main.run()
