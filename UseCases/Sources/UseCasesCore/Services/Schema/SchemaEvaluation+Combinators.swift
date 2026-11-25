/// `allOf`, `anyOf`, `oneOf`, `not`, and `if` with `then` and `else`.
extension SchemaEvaluation {
  func combinatorFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    var failures: [SchemaFailure] = []

    for index in node.allOf {
      failures += self.failures(
        of: value,
        at: path,
        against: index,
      )
    }
    failures += choiceFailures(
      of: value,
      at: path,
      node: node,
    )
    if let index = node.not, isValid(
      value,
      against: index,
    ) {
      failures.append(failure(
        path,
        .not,
        "\(value.schemaDescription) is not allowed",
      ))
    }

    return failures + conditionalFailures(
      of: value,
      at: path,
      node: node,
    )
  }

  /// `anyOf` and `oneOf` report once, at the value, whichever branch it missed.
  private func choiceFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    var failures: [SchemaFailure] = []

    if !node.anyOf.isEmpty, validCount(
      of: value,
      in: node.anyOf,
    ) == 0 {
      failures.append(failure(
        path,
        .anyOf,
        "\(value.schemaDescription) is not allowed",
      ))
    }
    if !node.oneOf.isEmpty {
      let count = validCount(
        of: value,
        in: node.oneOf,
      )
      if count != 1 {
        failures.append(failure(
          path,
          .oneOf,
          "\(value.schemaDescription) is not allowed",
        ))
      }
    }

    return failures
  }

  /// `then` applies when `if` holds and `else` when it does not; their failures are the value's.
  private func conditionalFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    guard let condition = node.condition else {
      return []
    }

    let branch = isValid(
      value,
      against: condition,
    ) ? node.consequence : node.alternative
    guard let branch else {
      return []
    }

    return failures(
      of: value,
      at: path,
      against: branch,
    )
  }

  private func validCount(
    of value: AuthoredValue,
    in indexes: [Int],
  ) -> Int {
    indexes.filter { isValid(
      value,
      against: $0,
    ) }.count
  }
}
