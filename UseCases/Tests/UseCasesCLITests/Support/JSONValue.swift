/// Any JSON value, read so that `true` and `1` stay different things.
enum JSONValue: Decodable, Equatable {
  case null
  case boolean(Bool)
  case integer(Int)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Int.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else {
      self = try .object(container.decode([String: JSONValue].self))
    }
  }

  /// The member of an object, or `nil` for anything else.
  subscript(key: String) -> JSONValue? {
    guard case let .object(members) = self else {
      return nil
    }

    return members[key]
  }
}
