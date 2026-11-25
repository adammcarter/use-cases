/// Reading a keyword's value as the kind of value the keyword takes.
extension SchemaCompilation {
  func string(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> String? {
    guard let value = keywords[keyword] else {
      return nil
    }
    guard case let .string(text) = value else {
      throw invalid(
        keyword,
        location: location,
      )
    }

    return text
  }

  /// A whole number from zero up, as `minLength` takes.
  func count(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> Int? {
    guard let value = keywords[keyword] else {
      return nil
    }
    guard case let .integer(count) = value, count >= 0 else {
      throw invalid(
        keyword,
        location: location,
      )
    }

    return count
  }

  func number(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> Double? {
    switch keywords[keyword] {
    case nil: nil
    case let .integer(integer): Double(integer)
    case let .number(number): number
    default: throw invalid(
        keyword,
        location: location,
      )
    }
  }

  func flag(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> Bool? {
    guard let value = keywords[keyword] else {
      return nil
    }
    guard case let .boolean(flag) = value else {
      throw invalid(
        keyword,
        location: location,
      )
    }

    return flag
  }

  func array(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> [AuthoredValue]? {
    guard let value = keywords[keyword] else {
      return nil
    }
    guard case let .array(elements) = value else {
      throw invalid(
        keyword,
        location: location,
      )
    }

    return elements
  }

  func strings(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> [String]? {
    guard let elements = try array(
      keyword,
      in: keywords,
      location: location,
    ) else {
      return nil
    }

    var texts: [String] = []
    for element in elements {
      guard case let .string(text) = element else {
        throw invalid(
          keyword,
          location: location,
        )
      }
      texts.append(text)
    }

    return texts
  }

  /// `type`: the name of a type, or a non-empty list of them.
  func types(
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> [SchemaType] {
    guard let value = keywords["type"] else {
      return []
    }

    let names: [String]
    switch value {
    case let .string(name):
      names = [name]
    case .array:
      names = try strings(
        "type",
        in: keywords,
        location: location,
      ) ?? []
    default:
      throw invalid(
        "type",
        location: location,
      )
    }

    var types: [SchemaType] = []
    for name in names {
      guard let type = SchemaType(rawValue: name) else {
        throw invalid(
          "type",
          location: location,
        )
      }
      types.append(type)
    }
    guard !types.isEmpty else {
      throw invalid(
        "type",
        location: location,
      )
    }

    return types
  }

  /// `dependentRequired`: for each member name, the names that must be written beside it.
  func dependentRequired(
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> [ExactText: [String]] {
    var dependencies: [ExactText: [String]] = [:]

    for member in try object(
      "dependentRequired",
      in: keywords,
      location: location,
    ) {
      guard case let .array(elements) = member.value else {
        throw invalid(
          "dependentRequired",
          location: location,
        )
      }

      var names: [String] = []
      for element in elements {
        guard case let .string(name) = element else {
          throw invalid(
            "dependentRequired",
            location: location,
          )
        }
        names.append(name)
      }
      dependencies[ExactText(member.key)] = names
    }

    return dependencies
  }

  func object(
    _ keyword: String,
    in keywords: Keywords,
    location: [String],
  ) throws(SchemaCompilerError) -> [AuthoredMember] {
    guard let value = keywords[keyword] else {
      return []
    }
    guard case let .object(members) = value else {
      throw invalid(
        keyword,
        location: location,
      )
    }

    return members
  }

  private func invalid(
    _ keyword: String,
    location: [String],
  ) -> SchemaCompilerError {
    .invalidKeywordValue(
      keyword,
      location: Self.text(of: location),
    )
  }
}
