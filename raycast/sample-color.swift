#!/usr/bin/swift

// Required parameters:
// @raycast.schemaVersion 1
// @raycast.title Sample Color
// @raycast.mode silent
//
// Optional parameters:
// @raycast.packageName System
//
// Documentation:
// @raycast.author Brian Kuzmanoski
// @raycast.authorURL https://github.com/bkuzmanoski
//
// Tweaked version of the original script by Jesse Claven (https://github.com/jesse-c)
// https://github.com/raycast/script-commands/blob/master/commands/system/sample-color.swift

import AppKit

extension NSColor {
  var hexAlphaString: String {
    let r: Int = lroundf(Float(redComponent) * 0xFF)
    let g: Int = lroundf(Float(greenComponent) * 0xFF)
    let b: Int = lroundf(Float(blueComponent) * 0xFF)
    return String(format: "#%02lx%02lx%02lx", r, g, b)
  }
}

func copyToPasteboard(_ color: String) {
  NSPasteboard.general.clearContents()
  NSPasteboard.general.writeObjects([color as NSPasteboardWriting])
}

let sampler: NSColorSampler = NSColorSampler()

sampler.show { selectedColor in
  if let selectedColor: NSColor = selectedColor {
    let hexTuple: String = selectedColor.hexAlphaString
    copyToPasteboard(hexTuple)
    print("Sampled color: \(hexTuple)")
    exit(0)
  } else {
    print("Sampled color: none")
    exit(0)
  }
}

RunLoop.main.run()
