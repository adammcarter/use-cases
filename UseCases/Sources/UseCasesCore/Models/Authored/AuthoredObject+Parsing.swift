extension AuthoredObject {
  /// The text under the key as an id, refusing text off the id grammar.
  func requiredIdentifier<Identifier>(
    _ key: String,
    parsing make: (String) throws(IdentityError) -> Identifier,
  ) throws(AuthoredShapeError) -> Identifier {
    let text = try requiredString(key)

    do {
      return try make(text)
    } catch {
      throw .invalidIdentifier(
        location: location(of: key),
        error,
      )
    }
  }

  /// The text under the key as an id when it is written.
  func optionalIdentifier<Identifier>(
    _ key: String,
    parsing make: (String) throws(IdentityError) -> Identifier,
  ) throws(AuthoredShapeError) -> Identifier? {
    guard contains(key) else {
      return nil
    }

    return try requiredIdentifier(
      key,
      parsing: make,
    )
  }

  /// The id of every item of the list under the key; an absent list is an empty one.
  func identifiers<Identifier>(
    _ key: String,
    parsing make: (String) throws(IdentityError) -> Identifier,
  ) throws(AuthoredShapeError) -> [Identifier] {
    var identifiers: [Identifier] = []

    for (index, text) in try strings(key).enumerated() {
      do {
        try identifiers.append(make(text))
      } catch {
        throw .invalidIdentifier(
          location: "\(location(of: key))[\(index)]",
          error,
        )
      }
    }

    return identifiers
  }

  func requiredPath(_ key: String) throws(AuthoredShapeError) -> WorkspacePath {
    try path(
      text: requiredString(key),
      at: location(of: key),
    )
  }

  /// The text under the key as a path, or the given text when the key is not written.
  func path(
    _ key: String,
    defaultText: String,
  ) throws(AuthoredShapeError) -> WorkspacePath {
    try path(
      text: optionalString(key) ?? defaultText,
      at: location(of: key),
    )
  }

  func requiredPattern(_ key: String) throws(AuthoredShapeError) -> PathPattern {
    try pattern(
      text: requiredString(key),
      at: location(of: key),
    )
  }

  /// The pattern of every item of the list under the key; an absent list is an empty one.
  func patterns(_ key: String) throws(AuthoredShapeError) -> [PathPattern] {
    var patterns: [PathPattern] = []

    for (index, text) in try strings(key).enumerated() {
      try patterns.append(
        pattern(
          text: text,
          at: "\(location(of: key))[\(index)]",
        ),
      )
    }

    return patterns
  }

  /// The mapping under the key as a position: a `line`, and a `column` when it is written.
  func optionalPosition(_ key: String) throws(AuthoredShapeError) -> SourcePosition? {
    guard let object = try optionalObject(key) else {
      return nil
    }

    let line = try object.requiredInteger("line")
    let column: Int? = if object.contains("column") {
      try object.requiredInteger("column")
    } else {
      nil
    }

    do {
      return try SourcePosition(
        line: line,
        column: column,
      )
    } catch {
      throw .invalidPosition(
        location: location(of: key),
        error,
      )
    }
  }

  /// The text under the key as a day written `YYYY-MM-DD`.
  func requiredDay(_ key: String) throws(AuthoredShapeError) -> String {
    let text = try requiredString(key)

    guard SchemaFormat.date.isValid(text) else {
      throw .invalidDate(
        location: location(of: key),
        text: text,
      )
    }

    return text
  }

  private func path(
    text: String,
    at location: String,
  ) throws(AuthoredShapeError) -> WorkspacePath {
    do {
      return try WorkspacePath(validating: text)
    } catch {
      throw .invalidPath(
        location: location,
        error,
      )
    }
  }

  private func pattern(
    text: String,
    at location: String,
  ) throws(AuthoredShapeError) -> PathPattern {
    do {
      return try PathPattern(validating: text)
    } catch {
      throw .invalidPattern(
        location: location,
        error,
      )
    }
  }
}
