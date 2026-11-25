/// The `settings` object of a bridge entry, passed unchanged to the transformer.
struct TransformerSettings: Decodable, Equatable, Sendable {
  static let empty = TransformerSettings(values: [:])

  let values: [String: JSONValue]

  init(values: [String: JSONValue]) {
    self.values = values
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    values = try container.decode([String: JSONValue].self)
  }

  /// The text under `name`, nil when absent.
  func string(_ name: String) throws(TransformerFailure) -> String? {
    guard let value = values[name], value != .null else {
      return nil
    }

    guard let text = value.stringValue else {
      throw .settingInvalid(
        name: name,
        expected: "text",
      )
    }

    return text
  }

  /// The text under `name`, which the transformer cannot work without.
  func requiredString(_ name: String) throws(TransformerFailure) -> String {
    guard let text = try string(name) else {
      throw .settingMissing(name)
    }

    return text
  }

  /// The whole number under `name`, nil when absent.
  func integer(_ name: String) throws(TransformerFailure) -> Int? {
    guard let value = values[name], value != .null else {
      return nil
    }

    guard let number = value.integerValue else {
      throw .settingInvalid(
        name: name,
        expected: "a whole number",
      )
    }

    return number
  }

  /// The true or false under `name`, nil when absent.
  func boolean(_ name: String) throws(TransformerFailure) -> Bool? {
    guard let value = values[name], value != .null else {
      return nil
    }

    guard let flag = value.boolValue else {
      throw .settingInvalid(
        name: name,
        expected: "true or false",
      )
    }

    return flag
  }

  /// The list of texts under `name`, nil when absent.
  func strings(_ name: String) throws(TransformerFailure) -> [String]? {
    guard let value = values[name], value != .null else {
      return nil
    }

    guard let items = value.arrayValue else {
      throw .settingInvalid(
        name: name,
        expected: "a list of text",
      )
    }

    return try items.map { item throws(TransformerFailure) in
      guard let text = item.stringValue else {
        throw .settingInvalid(
          name: name,
          expected: "a list of text",
        )
      }

      return text
    }
  }
}
