import UseCasesCore

/// How the TypeScript renderers read a loosely typed envelope: truthiness,
/// template-literal text and `padEnd`, over values that may be absent.
enum JavaScriptReading {
  /// Absent, `null`, `false`, `0`, `NaN` and `""` are falsy.
  static func isTruthy(_ value: JSONValue?) -> Bool {
    switch value {
    case .none, .null:
      false
    case let .bool(flag):
      flag
    case let .number(number):
      number != 0 && !number.isNaN
    case let .string(text):
      !text.isEmpty
    case .array, .object:
      true
    }
  }

  /// `${value}`: `undefined` when absent.
  static func text(_ value: JSONValue?) -> String {
    value.map(EnvelopeRenderer.scalarText) ?? "undefined"
  }

  /// `value ?? fallback` for a value that may be absent or null.
  static func present(_ value: JSONValue?) -> JSONValue? {
    value == .null ? nil : value
  }

  /// `text.padEnd(length)`, counted in UTF-16 units.
  static func padEnd(
    _ text: String,
    _ length: Int,
  ) -> String {
    text + String(repeating: " ", count: max(0, length - text.utf16.count))
  }

  /// A number read as JavaScript arithmetic reads a missing one: `NaN`.
  static func number(_ value: JSONValue?) -> Double {
    value?.numberValue ?? .nan
  }
}
