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
      JavaScriptNumber.parse(text)
    case .array, .object:
      JavaScriptNumber.parse(JavaScriptString.text(of: value))
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
}
