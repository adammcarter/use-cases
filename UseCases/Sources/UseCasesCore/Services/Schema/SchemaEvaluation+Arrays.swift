/// `items`, `minItems`, `maxItems` and `uniqueItems`.
extension SchemaEvaluation {
  func arrayFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    guard case let .array(elements) = value else {
      return []
    }

    var failures: [SchemaFailure] = []

    if let minimum = node.minItems, elements.count < minimum {
      failures.append(failure(
        path,
        .minItems,
        "\(value.schemaDescription) is too short (at least \(minimum) items)",
      ))
    }
    if let maximum = node.maxItems, elements.count > maximum {
      failures.append(failure(
        path,
        .maxItems,
        "\(value.schemaDescription) is too long (at most \(maximum) items)",
      ))
    }
    if node.requiresUniqueItems, hasDuplicates(elements) {
      failures.append(failure(
        path,
        .uniqueItems,
        "\(value.schemaDescription) has non-unique elements",
      ))
    }
    if let index = node.items {
      for (position, element) in elements.enumerated() {
        failures += self.failures(
          of: element,
          at: path + [.index(position)],
          against: index,
        )
      }
    }

    return failures
  }

  private func hasDuplicates(_ elements: [AuthoredValue]) -> Bool {
    for (position, element) in elements.enumerated()
      where element.isAmong(Array(elements[(position + 1)...]))
    {
      return true
    }

    return false
  }
}
