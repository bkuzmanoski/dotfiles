import AppKit

extension NSColor {
  var hexAlphaString: String {
    let redComponent = lroundf(Float(redComponent) * 0xFF)
    let greenComponent = lroundf(Float(greenComponent) * 0xFF)
    let blueComponent = lroundf(Float(blueComponent) * 0xFF)
    return String(format: "#%02lx%02lx%02lx", redComponent, greenComponent, blueComponent)
  }
}

NSColorSampler().show { sampledColor in
  if let hexTuple = sampledColor?.hexAlphaString {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([hexTuple as NSPasteboardWriting])
    print(hexTuple)
  }
  exit(0)
}

RunLoop.main.run()
