/// `type`, `$ref`, `const`, `enum` and `format`.
extension SchemaEvaluation {
  func typeFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    let isOfAType = node.types.contains { type in
      type.matches(value)
    }
    guard !node.types.isEmpty, !isOfAType else {
      return []
    }

    let names = node.types.map { type in
      "'\(type.rawValue)'"
    }.joined(separator: ", ")

    return [failure(
      path,
      .type,
      "\(value.schemaDescription) is not of type \(names)",
    )]
  }

  func valueFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    var failures: [SchemaFailure] = []

    if let reference = node.reference {
      failures += self.failures(
        of: value,
        at: path,
        against: reference,
      )
    }
    if let constant = node.constant, !constant.isSchemaEqual(to: value) {
      failures.append(failure(
        path,
        .const,
        "\(value.schemaDescription) is not allowed",
      ))
    }
    if let options = node.enumeration, !value.isAmong(options) {
      failures.append(failure(
        path,
        .enumeration,
        "\(value.schemaDescription) is not allowed",
      ))
    }
    if let format = node.format, case let .string(text) = value, !format.isValid(text) {
      failures.append(failure(
        path,
        .format,
        "\(value.schemaDescription) is not a '\(format.rawValue)'",
      ))
    }

    return failures
  }
}
