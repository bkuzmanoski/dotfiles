// Shared: Log

import AppKit

@main
enum PasteAsPlaintext {
  static func main() {
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
      Log.error("Failed to create CGEvent for paste action.")
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
  }
}
