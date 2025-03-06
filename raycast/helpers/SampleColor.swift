import AppKit

extension NSColor {
  var hexAlphaString: String {
    let r = lroundf(Float(redComponent) * 0xFF)
    let g = lroundf(Float(greenComponent) * 0xFF)
    let b = lroundf(Float(blueComponent) * 0xFF)
    return String(format: "#%02lx%02lx%02lx", r, g, b)
  }
}

NSColorSampler().show { sampledColor in
  if let hexTuple = sampledColor?.hexAlphaString {
    print(hexTuple)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([hexTuple as NSPasteboardWriting])
  }
}

RunLoop.main.run()
