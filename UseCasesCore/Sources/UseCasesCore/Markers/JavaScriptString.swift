/// The pieces of JavaScript's string behaviour the ledger code depends on,
/// spelled out over UTF-16 code units.
public enum JavaScriptString {
  /// `String.prototype.trim`: strips WhiteSpace and LineTerminator code units
  /// from both ends — including U+00A0, U+FEFF and U+2028, which Foundation's
  /// whitespace set does not agree on.
  public static func trim(_ text: String) -> String {
    let units = Array(text.utf16)
    var start = 0
    var end = units.count
    while start < end, CodeUnits.isJavaScriptWhitespace(units[start]) {
      start += 1
    }
    while end > start, CodeUnits.isJavaScriptWhitespace(units[end - 1]) {
      end -= 1
    }
    return CodeUnits.string(units[start ..< end])
  }

  /// `text.split(separator)` for a single code unit: every segment kept,
  /// including empty ones at either end.
  public static func split(
    _ text: String,
    on separator: UInt16,
  ) -> [String] {
    var segments: [String] = []
    var current: [UInt16] = []
    for unit in text.utf16 {
      if unit == separator {
        segments.append(CodeUnits.string(current))
        current = []
      } else {
        current.append(unit)
      }
    }
    segments.append(CodeUnits.string(current))
    return segments
  }

  /// JavaScript's `===` on strings: code units, not canonical equivalence.
  public static func identical(
    _ left: String,
    _ right: String,
  ) -> Bool {
    left.utf8.elementsEqual(right.utf8)
  }

  /// JavaScript's `<` on strings: UTF-16 code-unit order.
  static func precedes(
    _ left: String,
    _ right: String,
  ) -> Bool {
    left.utf16.lexicographicallyPrecedes(right.utf16)
  }

  /// `Array.prototype.sort()` on strings: code-unit order, stable.
  static func sorted(_ values: [String]) -> [String] {
    values.enumerated()
      .sorted { left, right in
        if precedes(left.element, right.element) {
          return true
        }
        if precedes(right.element, left.element) {
          return false
        }
        return left.offset < right.offset
      }
      .map(\.element)
  }

  /// `String(value)` for a parsed JSON value, or `"undefined"` when absent.
  ///
  /// Unlike ``JSONValue/javaScriptText``, an array spells a `null` element as
  /// the empty string, which is what `Array.prototype.join` does.
  static func text(of value: JSONValue?) -> String {
    guard let value else {
      return "undefined"
    }
    switch value {
    case let .array(elements):
      return elements
        .map { element in
          element == .null ? "" : text(of: element)
        }
        .joined(separator: ",")
    default:
      return value.javaScriptText
    }
  }
}
