/// A JSON document, in the shape the schema rules are evaluated against.
///
/// Objects keep their key order (see ``JSONObject``) and numbers are doubles,
/// because that is what JavaScript hands the TypeScript validator being ported:
/// `2.0` and `2` are the same value, and an integer keyword asks whether a
/// double happens to be whole.
public enum JSONValue: Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object(JSONObject)

  public var boolValue: Bool? {
    if case let .bool(value) = self {
      value
    } else {
      nil
    }
  }

  public var numberValue: Double? {
    if case let .number(value) = self {
      value
    } else {
      nil
    }
  }

  public var stringValue: String? {
    if case let .string(value) = self {
      value
    } else {
      nil
    }
  }

  public var arrayValue: [JSONValue]? {
    if case let .array(value) = self {
      value
    } else {
      nil
    }
  }

  public var objectValue: JSONObject? {
    if case let .object(value) = self {
      value
    } else {
      nil
    }
  }

  /// True for an object — and, as in JavaScript, false for an array.
  public var isRecord: Bool {
    if case .object = self {
      true
    } else {
      false
    }
  }

  /// The JSON type name, as the `type` keyword spells it.
  public var typeName: String {
    switch self {
    case .null: "null"
    case .bool: "boolean"
    case .number: "number"
    case .string: "string"
    case .array: "array"
    case .object: "object"
    }
  }

  public subscript(key: String) -> JSONValue? {
    objectValue?[key]
  }

  /// The value as JavaScript's `String(value)` would spell it. Used for the
  /// `(allowed: ...)` suffix on an enum diagnostic.
  var javaScriptText: String {
    switch self {
    case .null: "null"
    case let .bool(value): value ? "true" : "false"
    case let .number(value): JavaScriptNumber.text(value)
    case let .string(value): value
    case let .array(values): values.map(\.javaScriptText).joined(separator: ",")
    case .object: "[object Object]"
    }
  }
}
