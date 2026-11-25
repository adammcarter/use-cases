/// `pattern`, `minLength`, `maxLength`, `minimum` and `maximum`.
extension SchemaEvaluation {
  func stringFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    guard case let .string(text) = value else {
      return []
    }

    var failures: [SchemaFailure] = []
    let length = text.unicodeScalars.count

    if let minimum = node.minLength, length < minimum {
      failures.append(failure(
        path,
        .minLength,
        "\(value.schemaDescription) is too short (at least \(minimum) characters)",
      ))
    }
    if let maximum = node.maxLength, length > maximum {
      failures.append(failure(
        path,
        .maxLength,
        "\(value.schemaDescription) is too long (at most \(maximum) characters)",
      ))
    }
    if let source = node.pattern, !matches(
      text,
      pattern: source,
    ) {
      failures.append(failure(
        path,
        .pattern,
        "\(value.schemaDescription) is not allowed",
      ))
    }

    return failures
  }

  func numberFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    guard let number = value.numericValue else {
      return []
    }

    var failures: [SchemaFailure] = []

    if let minimum = node.minimum, number < minimum {
      failures.append(failure(
        path,
        .minimum,
        "\(value.schemaDescription) is less than the minimum of \(minimum.schemaNumberText)",
      ))
    }
    if let maximum = node.maximum, number > maximum {
      failures.append(failure(
        path,
        .maximum,
        "\(value.schemaDescription) is greater than the maximum of \(maximum.schemaNumberText)",
      ))
    }

    return failures
  }

  /// A pattern is a search, not a match of the whole text: it may match anywhere in it.
  private func matches(
    _ text: String,
    pattern: String,
  ) -> Bool {
    guard let regex = patterns[ExactText(pattern)] else {
      return false
    }

    return text.firstMatch(of: regex) != nil
  }
}
