/// An authored mapping being read, with the place it sits in the document, so every refusal says
/// where it is. Members are found by their exact UTF-8 spelling.
struct AuthoredObject: Sendable {
  let members: [AuthoredMember]

  /// Where the mapping sits, such as `validation[0]`; empty for the whole document.
  let location: String

  /// Reads a value as a mapping, refusing anything else.
  init(
    _ value: AuthoredValue,
    at location: String,
  ) throws(AuthoredShapeError) {
    guard case let .object(members) = value else {
      throw .notAnObject(location: location)
    }

    self.members = members
    self.location = location
  }

  /// The place of a member of this mapping, such as `validation[0].covers`.
  func location(of key: String) -> String {
    location.isEmpty ? key : "\(location).\(key)"
  }

  /// Whether the mapping writes the key.
  func contains(_ key: String) -> Bool {
    value(for: key) != nil
  }

  /// The value written under the key, when there is one.
  func value(for key: String) -> AuthoredValue? {
    members.first { member in
      member.key.isExactlyEqual(to: key)
    }?.value
  }

  func requiredString(_ key: String) throws(AuthoredShapeError) -> String {
    guard let value = value(for: key) else {
      throw .missing(location: location(of: key))
    }

    return try string(
      value,
      at: location(of: key),
    )
  }

  func optionalString(_ key: String) throws(AuthoredShapeError) -> String? {
    guard let value = value(for: key) else {
      return nil
    }

    return try string(
      value,
      at: location(of: key),
    )
  }

  func requiredInteger(_ key: String) throws(AuthoredShapeError) -> Int {
    guard let value = value(for: key) else {
      throw .missing(location: location(of: key))
    }

    switch value {
    case let .integer(integer):
      return integer
    case let .number(number):
      // `40.0` is a whole number to the schema, so it is one here.
      if let integer = Int(exactly: number) {
        return integer
      }
    default:
      break
    }

    throw .wrongType(
      location: location(of: key),
      expected: "a whole number",
    )
  }

  func optionalBoolean(_ key: String) throws(AuthoredShapeError) -> Bool? {
    guard let value = value(for: key) else {
      return nil
    }

    guard case let .boolean(flag) = value else {
      throw .wrongType(
        location: location(of: key),
        expected: "true or false",
      )
    }

    return flag
  }

  /// The mapping under the key, when it is written.
  func optionalObject(_ key: String) throws(AuthoredShapeError) -> AuthoredObject? {
    guard let value = value(for: key) else {
      return nil
    }

    return try AuthoredObject(
      value,
      at: location(of: key),
    )
  }

  func requiredObject(_ key: String) throws(AuthoredShapeError) -> AuthoredObject {
    guard let object = try optionalObject(key) else {
      throw .missing(location: location(of: key))
    }

    return object
  }

  /// The text of every item of the list under the key; an absent list is an empty one.
  func strings(_ key: String) throws(AuthoredShapeError) -> [String] {
    var texts: [String] = []

    for (index, item) in try items(key).enumerated() {
      try texts.append(
        string(
          item,
          at: "\(location(of: key))[\(index)]",
        ),
      )
    }

    return texts
  }

  /// Every item of the list under the key as a mapping; an absent list is an empty one.
  func objects(_ key: String) throws(AuthoredShapeError) -> [AuthoredObject] {
    var objects: [AuthoredObject] = []

    for (index, item) in try items(key).enumerated() {
      try objects.append(
        AuthoredObject(
          item,
          at: "\(location(of: key))[\(index)]",
        ),
      )
    }

    return objects
  }

  /// The list under the key; an absent list is an empty one.
  func items(_ key: String) throws(AuthoredShapeError) -> [AuthoredValue] {
    guard let value = value(for: key) else {
      return []
    }

    guard case let .array(items) = value else {
      throw .wrongType(
        location: location(of: key),
        expected: "a list",
      )
    }

    return items
  }

  /// The value under the key as one of the cases of a type written as text.
  func requiredChoice<Choice: RawRepresentable>(
    _ key: String,
    as _: Choice.Type,
  ) throws(AuthoredShapeError) -> Choice where Choice.RawValue == String {
    let text = try requiredString(key)

    guard let choice = Choice(rawValue: text) else {
      throw .unknownChoice(
        location: location(of: key),
        text: text,
      )
    }

    return choice
  }

  func optionalChoice<Choice: RawRepresentable>(
    _ key: String,
    as type: Choice.Type,
  ) throws(AuthoredShapeError) -> Choice? where Choice.RawValue == String {
    guard contains(key) else {
      return nil
    }

    return try requiredChoice(
      key,
      as: type,
    )
  }

  private func string(
    _ value: AuthoredValue,
    at location: String,
  ) throws(AuthoredShapeError) -> String {
    guard case let .string(text) = value else {
      throw .wrongType(
        location: location,
        expected: "text",
      )
    }

    return text
  }
}
