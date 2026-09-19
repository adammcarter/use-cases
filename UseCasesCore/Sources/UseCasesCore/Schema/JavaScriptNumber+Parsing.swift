/// JavaScript's `Number(string)`: the other direction from ``text(_:)``.
public extension JavaScriptNumber {
  /// `StringToNumber`: surrounding whitespace ignored, empty is zero, a
  /// decimal literal or `Infinity` with an optional sign, or an unsigned
  /// `0x`/`0o`/`0b` integer; anything else is NaN.
  static func parse(_ text: String) -> Double {
    let trimmed = JavaScriptString.trim(text)
    if trimmed.isEmpty {
      return 0
    }
    if let radixValue = radixInteger(trimmed) {
      return radixValue
    }
    var body = Substring(trimmed)
    var sign = 1.0
    if let first = body.first, first == "+" || first == "-" {
      sign = first == "-" ? -1 : 1
      body = body.dropFirst()
    }
    if body == "Infinity" {
      return sign * .infinity
    }
    guard isDecimalLiteral(body), let magnitude = Double(body) else {
      return .nan
    }
    return sign * magnitude
  }

  private static func radixInteger(_ text: String) -> Double? {
    let units = Array(text.utf8)
    guard units.count > 2, units[0] == UInt8(ascii: "0") else {
      return nil
    }
    let radix: Double
    switch units[1] {
    case UInt8(ascii: "x"), UInt8(ascii: "X"): radix = 16
    case UInt8(ascii: "o"), UInt8(ascii: "O"): radix = 8
    case UInt8(ascii: "b"), UInt8(ascii: "B"): radix = 2
    default: return nil
    }
    var total = 0.0
    for unit in units.dropFirst(2) {
      guard let digit = hexadecimalDigit(unit), Double(digit) < radix else {
        return .nan
      }
      total = total * radix + Double(digit)
    }
    return total
  }

  private static func hexadecimalDigit(_ unit: UInt8) -> Int? {
    switch unit {
    case UInt8(ascii: "0") ... UInt8(ascii: "9"): Int(unit - UInt8(ascii: "0"))
    case UInt8(ascii: "a") ... UInt8(ascii: "f"): Int(unit - UInt8(ascii: "a")) + 10
    case UInt8(ascii: "A") ... UInt8(ascii: "F"): Int(unit - UInt8(ascii: "A")) + 10
    default: nil
    }
  }

  /// `digits [. digits] [e [+-] digits]` or `. digits [exponent]`.
  private static func isDecimalLiteral(_ text: Substring) -> Bool {
    let units = Array(text.utf8)
    var index = 0
    func digits() -> Int {
      let start = index
      while index < units.count, units[index] >= UInt8(ascii: "0"),
            units[index] <= UInt8(ascii: "9")
      {
        index += 1
      }
      return index - start
    }
    var mantissaDigits = digits()
    if index < units.count, units[index] == UInt8(ascii: ".") {
      index += 1
      mantissaDigits += digits()
    }
    guard mantissaDigits > 0 else {
      return false
    }
    if index < units.count, units[index] == UInt8(ascii: "e") || units[index] == UInt8(ascii: "E") {
      index += 1
      if index < units.count,
         units[index] == UInt8(ascii: "+") || units[index] == UInt8(ascii: "-")
      {
        index += 1
      }
      guard digits() > 0 else {
        return false
      }
    }
    return index == units.count
  }
}
