import Foundation

let inputData = FileHandle.standardInput.availableData
guard let inputText = String(data: inputData, encoding: .utf8), !inputText.isEmpty else {
  print("No input provided. Pipe some text into this command.")
  exit(1)
}

guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
  print("Could not create detector.")
  exit(1)
}

let matches = detector.matches(in: inputText, options: [], range: NSRange(location: 0, length: inputText.utf16.count))
for match in matches { if let url = match.url?.absoluteString { print(url) } }
