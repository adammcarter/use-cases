import Foundation

/// Any JSON value: transformer settings and the lines of a test tool's report are read through it,
/// so a field of an unexpected type is a missing value, never a crash.
enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  case integer(Int)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  /// The value spelled by `text`, or nil when `text` is not JSON.
  static func parse(_ text: String) -> JSONValue? {
    try? JSONDecoder().decode(
      JSONValue.self,
      from: Data(text.utf8),
    )
  }

  subscript(key: String) -> JSONValue? {
    guard case let .object(members) = self else {
      return nil
    }

    return members[key]
  }

  var stringValue: String? {
    guard case let .string(text) = self else {
      return nil
    }

    return text
  }

  var integerValue: Int? {
    guard case let .integer(number) = self else {
      return nil
    }

    return number
  }

  var boolValue: Bool? {
    guard case let .bool(flag) = self else {
      return nil
    }

    return flag
  }

  var arrayValue: [JSONValue]? {
    guard case let .array(items) = self else {
      return nil
    }

    return items
  }
}

extension JSONValue: Decodable {
  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let flag = try? container.decode(Bool.self) {
      self = .bool(flag)
    } else if let number = try? container.decode(Int.self) {
      self = .integer(number)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let text = try? container.decode(String.self) {
      self = .string(text)
    } else if let items = try? container.decode([JSONValue].self) {
      self = .array(items)
    } else {
      self = try .object(container.decode([String: JSONValue].self))
    }
  }
}
