import AppKit
import System

struct FileDescriptorOutputStream: TextOutputStream {
  static var standardError = FileDescriptorOutputStream(.standardError)
  static var standardOutput = FileDescriptorOutputStream(.standardOutput)

  let fileDescriptor: FileDescriptor
  var errorHandler: ((any Error) -> Void)?

  init(_ fileDescriptor: FileDescriptor, errorHandler: ((any Error) -> Void)? = nil) {
    self.fileDescriptor = fileDescriptor
    self.errorHandler = errorHandler
  }

  mutating func write(_ string: String) {
    do {
      try fileDescriptor.writeAll(string.utf8)
    } catch {
      errorHandler?(error)
    }
  }
}

let pasteboard = NSPasteboard.general

guard
  let pasteboardItems = pasteboard.pasteboardItems,
  let plaintext = pasteboard.string(forType: .string)
else {
  exit(EXIT_SUCCESS)
}

guard
  let source = CGEventSource(stateID: .hidSystemState),
  let pasteKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true),
  let pasteKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false)
else {
  print("Failed to create CGEvent for paste action.", to: &FileDescriptorOutputStream.standardError)
  exit(EXIT_FAILURE)
}

pasteKeyDown.flags = .maskCommand
pasteKeyUp.flags = .maskCommand

let preservedItems = pasteboardItems.map { item -> NSPasteboardItem in
  let preservedItem = NSPasteboardItem()

  for itemType in item.types {
    if let data = item.data(forType: itemType) {
      preservedItem.setData(data, forType: itemType)
    }
  }

  return preservedItem
}

pasteboard.clearContents()
pasteboard.setString(plaintext, forType: .string)

Thread.sleep(forTimeInterval: 0.05)
pasteKeyDown.post(tap: .cghidEventTap)

Thread.sleep(forTimeInterval: 0.05)
pasteKeyUp.post(tap: .cghidEventTap)

Thread.sleep(forTimeInterval: 0.05)
pasteboard.clearContents()
pasteboard.writeObjects(preservedItems)
