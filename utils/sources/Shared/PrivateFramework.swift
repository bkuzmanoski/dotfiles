import Foundation

struct PrivateFramework {
  enum Error: Swift.Error, LocalizedError {
    case failedToLoadFramework(name: String, reason: String?)
    case missingSymbol(name: String)

    var errorDescription: String? {
      switch self {
      case .failedToLoadFramework(let name, let reason):
        "Failed to load the \(name) framework\(reason.map { ": \($0)" } ?? ".")"

      case .missingSymbol(let name):
        "Missing symbol: \(name)"
      }
    }
  }

  private let handle: UnsafeMutableRawPointer

  init(named name: String) throws {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/\(name).framework/\(name)", RTLD_LAZY) else {
      throw Error.failedToLoadFramework(name: name, reason: dlerror().map { String(cString: $0) })
    }

    self.handle = handle
  }

  func symbol<Symbol>(named name: String) throws -> Symbol {
    return unsafeBitCast(try address(ofSymbolNamed: name), to: Symbol.self)
  }

  func constant<Value>(named name: String) throws -> Value {
    return try address(ofSymbolNamed: name).load(as: Value.self)
  }

  private func address(ofSymbolNamed name: String) throws -> UnsafeMutableRawPointer {
    guard let address = dlsym(handle, name) else {
      throw Error.missingSymbol(name: name)
    }

    return address
  }
}
