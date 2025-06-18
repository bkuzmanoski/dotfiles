import AppKit

let pasteboard = NSPasteboard.general

guard
  let pasteboardItems = pasteboard.pasteboardItems,
  let plaintext = pasteboard.string(forType: .string)
else {
  exit(0)
}

guard
  let source = CGEventSource(stateID: .hidSystemState),
  let pasteKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: true),
  let pasteKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(9), keyDown: false)
else {
  print("Failed to create event source")
  exit(1)
}

pasteKeyDown.flags = .maskCommand
pasteKeyUp.flags = .maskCommand

let preservedItems = pasteboardItems.map { item -> NSPasteboardItem in
  let preservedItem = NSPasteboardItem()
  item.types.forEach { type in
    if let data = item.data(forType: type) {
      preservedItem.setData(data, forType: type)
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
