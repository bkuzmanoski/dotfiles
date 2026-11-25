import Foundation

extension OSStatus {
  var fourCharCodeString: String? {
    let bytes = [
      UInt8((self >> 24) & 0xff),
      UInt8((self >> 16) & 0xff),
      UInt8((self >> 8) & 0xff),
      UInt8(self & 0xff)
    ]

    guard bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }) else {
      return nil
    }

    let scalars = bytes.compactMap { UnicodeScalar($0) }

    return String(String.UnicodeScalarView(scalars))
  }

  var statusDescription: String { fourCharCodeString.map { "\($0) (\(self))" } ?? String(self) }
}
