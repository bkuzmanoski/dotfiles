import Foundation

struct FixedPointFormatStyle: FormatStyle {
  typealias FormatInput = Double
  typealias FormatOutput = String

  var fractionLength: Int

  func format(_ value: Double) -> String {
    var multiplier = 1

    for _ in 0..<fractionLength {
      multiplier *= 10
    }

    let scaledValue = Int((value * Double(multiplier)).rounded())

    guard fractionLength > 0 else {
      return String(scaledValue)
    }

    let fractionDigits = String(scaledValue % multiplier)
    let fractionPadding = String(repeating: "0", count: fractionLength - fractionDigits.count)

    return "\(scaledValue / multiplier).\(fractionPadding)\(fractionDigits)"
  }
}

extension FormatStyle where Self == FixedPointFormatStyle {
  static func fixedPoint(fractionLength: Int) -> FixedPointFormatStyle {
    return FixedPointFormatStyle(fractionLength: fractionLength)
  }
}
