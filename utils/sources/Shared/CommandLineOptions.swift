// Shared: Log

import Foundation

enum CommandLineOptionsError: Error {
  case helpRequested
  case invalidUsage(String)
}

protocol ParsableCommandLineOptions {
  static var usageDescription: String { get }

  init(arguments: some Sequence<String>) throws(CommandLineOptionsError)
}

extension ParsableCommandLineOptions {
  static func parseOrExit() -> Self {
    do {
      return try Self(arguments: CommandLine.arguments.dropFirst())
    } catch {
      switch error {
      case .helpRequested:
        print(usageDescription)
        exit(EXIT_SUCCESS)

      case .invalidUsage(let message):
        Log.error("Error: \(message)\n\n\(usageDescription)")
        exit(EX_USAGE)
      }
    }
  }
}
