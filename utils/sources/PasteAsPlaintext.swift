import AppKit
import Synchronization
import System

enum Log {
  enum Error: Swift.Error, LocalizedError {
    case outputAlreadyRedirected

    var errorDescription: String? {
      switch self {
      case .outputAlreadyRedirected: "Output has already been redirected."
      }
    }
  }

  private static let timestampStyle =
    isatty(FileDescriptor.standardOutput.rawValue) == 0
    ? Date.ISO8601FormatStyle(
      dateTimeSeparator: .space,
      includingFractionalSeconds: true,
      timeZone: .current
    ) : nil
  private static let isRedirected = Atomic(false)

  static func redirectOutput(to filePath: FilePath) throws {
    let (exchanged, _) = isRedirected.compareExchange(
      expected: false,
      desired: true,
      ordering: .acquiringAndReleasing
    )

    guard exchanged else {
      throw Error.outputAlreadyRedirected
    }

    do {
      let fileDescriptor = try FileDescriptor.open(
        filePath,
        .writeOnly,
        options: [.create, .truncate, .append],
        permissions: [.ownerReadWrite, .groupRead, .otherRead]
      )

      try fileDescriptor.closeAfter {
        _ = try fileDescriptor.duplicate(as: .standardOutput)
        _ = try fileDescriptor.duplicate(as: .standardError)
      }

      setvbuf(stdout, nil, _IONBF, 0)
      setvbuf(stderr, nil, _IONBF, 0)
    } catch {
      isRedirected.store(false, ordering: .releasing)
      throw error
    }
  }

  static func message(_ message: String) {
    write(message, to: .standardOutput)
  }

  static func error(_ message: String) {
    write(message, to: .standardError)
  }

  private static func write(_ message: String, to fileDescriptor: FileDescriptor) {
    _ = try? fileDescriptor.writeAll(line(for: message).utf8)
  }

  private static func line(for message: String) -> String {
    guard let timestampStyle else {
      return "\(message)\n"
    }

    return "[\(Date.now.formatted(timestampStyle))] \(message)\n"
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
