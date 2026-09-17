import Foundation

/// Spells a double the way JavaScript's `JSON.stringify` spells it.
///
/// Semantic hashes are taken over `JSON.stringify` output, so a number that is
/// spelled `1.0` instead of `1`, or `1e-07` instead of `1e-7`, changes a digest
/// that is written into evidence ledgers.
enum JavaScriptNumber {
  /// The `JSON.stringify` spelling of `value` — `null` when it is not finite.
  static func text(_ value: Double) -> String {
    guard value.isFinite else {
      return "null"
    }
    if value == 0 {
      return "0"
    }
    let sign = value < 0 ? "-" : ""
    let (digits, pointPosition) = shortestDigits(abs(value))
    return sign + spell(digits: digits, pointPosition: pointPosition)
  }

  /// The shortest digit string that reads back as `value`, with the position of
  /// the decimal point relative to it (ECMA-262's `k` and `n`).
  private static func shortestDigits(_ value: Double) -> (digits: String, pointPosition: Int) {
    for precision in 0 ... 17 {
      let candidate = String(format: "%.\(precision)e", value)
      if Double(candidate) == value {
        return split(candidate)
      }
    }
    return split(String(format: "%.17e", value))
  }

  /// Split a `d.ddde±dd` spelling into its digits and decimal point position.
  private static func split(_ exponentialText: String) -> (digits: String, pointPosition: Int) {
    let parts = exponentialText.split(separator: "e")
    let mantissa = parts.first.map(String.init) ?? "0"
    let exponent = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
    var digits = mantissa.replacingOccurrences(of: ".", with: "")
    while digits.count > 1, digits.hasSuffix("0") {
      digits.removeLast()
    }
    return (digits, exponent + 1)
  }

  /// ECMA-262 `Number::toString`, step 5 onwards: plain notation while the
  /// point sits within the digits or close to them, exponential beyond.
  private static func spell(
    digits: String,
    pointPosition: Int,
  ) -> String {
    let count = digits.count
    if count <= pointPosition, pointPosition <= 21 {
      return digits + String(repeating: "0", count: pointPosition - count)
    }
    if pointPosition > 0, pointPosition <= 21 {
      let head = digits.prefix(pointPosition)
      let tail = digits.dropFirst(pointPosition)
      return "\(head).\(tail)"
    }
    if pointPosition > -6, pointPosition <= 0 {
      return "0." + String(repeating: "0", count: -pointPosition) + digits
    }
    let exponent = pointPosition - 1
    let exponentSign = exponent >= 0 ? "+" : "-"
    let leading = digits.prefix(1)
    let rest = digits.dropFirst()
    let mantissa = rest.isEmpty ? String(leading) : "\(leading).\(rest)"
    return "\(mantissa)e\(exponentSign)\(abs(exponent))"
  }
}
