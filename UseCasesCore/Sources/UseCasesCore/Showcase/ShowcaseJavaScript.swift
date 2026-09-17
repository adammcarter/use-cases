import Foundation

/// How the showcase TypeScript reads the JSON a run ledger line holds.
///
/// A ledger line is kept if it merely PARSES, so every member the code reads
/// may be any JSON value, or absent (Swift's nil standing for `undefined`).
/// Reading a member of `null` or `undefined` is a TypeError, raised here with
/// V8's text; reading one of any other non-object is `undefined`, since no
/// member the showcase code reads exists on a string, number, boolean or array.
enum ShowcaseJavaScript {
  /// `value.key`.
  static func member(
    _ value: JSONValue?,
    _ key: String,
  ) throws(ShowcaseError) -> JSONValue? {
    switch value {
    case .none:
      throw .unreadableEvent(message: "Cannot read properties of undefined (reading '\(key)')")
    case .null:
      throw .unreadableEvent(message: "Cannot read properties of null (reading '\(key)')")
    case let .object(object):
      return object[key]
    default:
      return nil
    }
  }

  /// `value?.key`.
  static func optionalMember(
    _ value: JSONValue?,
    _ key: String,
  ) -> JSONValue? {
    value?.objectValue?[key]
  }

  /// `value === text`.
  static func isString(
    _ value: JSONValue?,
    _ text: String,
  ) -> Bool {
    JavaScriptValue.strictlyEquals(value, text)
  }

  /// `(value ?? [])` where the TypeScript then calls an array method on it:
  /// nullish reads as empty, an array as its elements, and anything else is
  /// V8's "is not a function".
  static func arrayOrEmpty(
    _ value: JSONValue?,
    calling method: String,
  ) throws(ShowcaseError) -> [JSONValue] {
    switch value {
    case .none, .null:
      return []
    case let .array(elements):
      return elements
    default:
      throw .unreadableEvent(message: "((intermediate value) ?? []).\(method) is not a function")
    }
  }

  /// `for (const x of value ?? [])`: a string iterates its code points.
  static func iterated(_ value: JSONValue?) throws(ShowcaseError) -> [JSONValue] {
    switch value {
    case .none, .null:
      return []
    case let .array(elements):
      return elements
    case let .string(text):
      return text.unicodeScalars.map { scalar in
        .string(String(scalar))
      }
    case let .number(number):
      throw notIterable("number \(JavaScriptNumber.text(number))")
    case let .bool(flag):
      throw notIterable("boolean \(flag)")
    case .object:
      throw notIterable("object")
    }
  }

  private static func notIterable(_ spelled: String) -> ShowcaseError {
    .unreadableEvent(
      message: "\(spelled) is not iterable (cannot read property Symbol(Symbol.iterator))",
    )
  }

  /// `.length` of a value known not to be nullish.
  static func length(of value: JSONValue) -> JSONValue? {
    switch value {
    case let .array(elements):
      .number(Double(elements.count))
    case let .string(text):
      .number(Double(text.utf16.count))
    case let .object(object):
      object["length"]
    default:
      nil
    }
  }

  /// `{ ...value }`: an object's members, a string's or array's indices, and
  /// nothing for any other value.
  static func spread(_ value: JSONValue?) -> JSONObject {
    switch value {
    case let .object(object):
      object
    case let .array(elements):
      JSONObject(elements.enumerated().map { index, element in
        (String(index), element)
      })
    case let .string(text):
      JSONObject(text.utf16.enumerated().map { index, unit in
        (String(index), .string(CodeUnits.string([unit])))
      })
    default:
      JSONObject()
    }
  }

  // MARK: - Numbers and comparison

  /// `Number(value)`, through `ToPrimitive` for arrays and objects.
  static func toNumber(_ value: JSONValue?) -> Double {
    switch value {
    case .none:
      .nan
    case .null:
      0
    case let .bool(flag):
      flag ? 1 : 0
    case let .number(number):
      number
    case let .string(text):
      stringToNumber(text)
    case .array, .object:
      stringToNumber(JavaScriptString.text(of: value))
    }
  }

  /// `left > right`, JavaScript's abstract relational comparison: two strings
  /// (after `ToPrimitive`) compare by code unit, anything else as numbers.
  static func greaterThan(
    _ left: JSONValue?,
    _ right: JSONValue?,
  ) -> Bool {
    if let leftText = primitiveString(left), let rightText = primitiveString(right) {
      return JavaScriptString.precedes(rightText, leftText)
    }
    return toNumber(left) > toNumber(right)
  }

  /// The string a value's `ToPrimitive` yields, when it yields one.
  private static func primitiveString(_ value: JSONValue?) -> String? {
    switch value {
    case let .string(text):
      text
    case .array, .object:
      JavaScriptString.text(of: value)
    default:
      nil
    }
  }

  /// `StringToNumber`: surrounding whitespace ignored, empty is zero, a
  /// decimal literal or `Infinity` with an optional sign, or an unsigned
  /// `0x`/`0o`/`0b` integer; anything else is NaN.
  static func stringToNumber(_ text: String) -> Double {
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
