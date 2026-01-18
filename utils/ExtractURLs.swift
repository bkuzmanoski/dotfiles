import Foundation

guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
  FileHandle.standardError.write(Data("Error: Failed to initialize data detector.\n".utf8))
  exit(1)
}

while let line = readLine() {
  let range = NSRange(line.startIndex..<line.endIndex, in: line)
  detector.enumerateMatches(in: line, options: [], range: range) { (match, _, _) in
    if let url = match?.url {
      print(url.absoluteString)
    }
  }
}
