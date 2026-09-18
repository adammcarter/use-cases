import Foundation

/// The JSON the oracle reads off a binary's stdout.
///
/// The oracle links nothing, so it cannot borrow `UseCasesCore`'s `JSONValue`:
/// a black-box test that decoded with the product's own decoder would stop
/// being black-box the moment that decoder was wrong. This is a small,
/// independent reader built on `JSONSerialization`.
enum OracleJson: Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([OracleJson])
  case object([String: OracleJson])

  static func parse(_ text: String) throws -> OracleJson {
    let data = Data(text.utf8)
    let decoded = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    return OracleJson(decoded)
  }

  init(_ any: Any) {
    switch any {
    case let value as [Any]:
      self = .array(value.map(OracleJson.init))
    case let value as [String: Any]:
      self = .object(value.mapValues(OracleJson.init))
    case let value as String:
      self = .string(value)
    case let value as NSNumber:
      self = CFGetTypeID(value) == CFBooleanGetTypeID()
        ? .bool(value.boolValue)
        : .number(value.doubleValue)
    default:
      self = .null
    }
  }

  subscript(key: String) -> OracleJson? {
    guard case let .object(members) = self else {
      return nil
    }
    return members[key]
  }

  subscript(index: Int) -> OracleJson? {
    guard case let .array(elements) = self, elements.indices.contains(index) else {
      return nil
    }
    return elements[index]
  }

  /// Follow a dotted path, e.g. `"data.gate.bar"`. Missing members give nil.
  func at(_ path: String) -> OracleJson? {
    path.split(separator: ".").reduce(self as OracleJson?) { node, step in
      if let index = Int(step) {
        return node?[index]
      }
      return node?[String(step)]
    }
  }

  var stringValue: String? {
    guard case let .string(value) = self else {
      return nil
    }
    return value
  }

  var boolValue: Bool? {
    guard case let .bool(value) = self else {
      return nil
    }
    return value
  }

  var intValue: Int? {
    guard case let .number(value) = self else {
      return nil
    }
    return Int(value)
  }

  var doubleValue: Double? {
    guard case let .number(value) = self else {
      return nil
    }
    return value
  }

  var arrayValue: [OracleJson]? {
    guard case let .array(value) = self else {
      return nil
    }
    return value
  }

  var objectValue: [String: OracleJson]? {
    guard case let .object(value) = self else {
      return nil
    }
    return value
  }

  var isNull: Bool {
    self == .null
  }

  /// Every string value anywhere beneath this node, in no particular order.
  ///
  /// `JSON.stringify(x).toContain("…")` is how the TypeScript oracle asks "is
  /// this code anywhere in here"; ``encoded`` answers the same question, and
  /// this answers the narrower one without matching a key name by accident.
  var allStrings: [String] {
    switch self {
    case let .string(value):
      [value]
    case let .array(elements):
      elements.flatMap(\.allStrings)
    case let .object(members):
      members.values.flatMap(\.allStrings)
    default:
      []
    }
  }

  /// A deterministic serialisation, for `contains` assertions and failure text.
  ///
  /// Keys are sorted, which `JSON.stringify` does not do — no oracle assertion
  /// depends on key ORDER (the frozen envelope constrains keys and types, not
  /// their order on the wire), and a stable string makes a failure readable.
  var encoded: String {
    switch self {
    case .null:
      "null"
    case let .bool(value):
      value ? "true" : "false"
    case let .number(value):
      Self.encodedNumber(value)
    case let .string(value):
      Self.quoted(value)
    case let .array(elements):
      "[" + elements.map(\.encoded).joined(separator: ",") + "]"
    case let .object(members):
      "{" + members.keys.sorted().map { key in
        // swiftlint:disable:next force_unwrapping
        Self.quoted(key) + ":" + members[key]!.encoded
      }.joined(separator: ",") + "}"
    }
  }

  private static func encodedNumber(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 {
      return String(Int64(value))
    }
    return String(value)
  }

  private static func quoted(_ value: String) -> String {
    let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
    guard let data, let text = String(data: data, encoding: .utf8) else {
      return "\"\(value)\""
    }
    return String(text.dropFirst().dropLast())
  }
}
