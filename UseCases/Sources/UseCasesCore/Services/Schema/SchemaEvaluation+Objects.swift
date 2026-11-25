/// `required`, `dependentRequired`, `properties`, `additionalProperties` and `propertyNames`.
extension SchemaEvaluation {
  func objectFailures(
    of value: AuthoredValue,
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    guard case let .object(members) = value else {
      return []
    }

    return requiredFailures(
      members: members,
      at: path,
      node: node,
    ) + dependencyFailures(
      members: members,
      at: path,
      node: node,
    ) + propertyFailures(
      members: members,
      at: path,
      node: node,
    ) + additionalFailures(
      members: members,
      at: path,
      node: node,
    ) + nameFailures(
      members: members,
      at: path,
      node: node,
    )
  }

  private func requiredFailures(
    members: [AuthoredMember],
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    node.required.compactMap { name in
      members.contains {
        $0.key.hasSameScalars(as: name)
      }
        ? nil
        : failure(
          path,
          .required,
          "\(AuthoredValue.quote(name)) is a required property",
          members: [name],
        )
    }
  }

  /// A member that is written needs the members it depends on.
  private func dependencyFailures(
    members: [AuthoredMember],
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    var failures: [SchemaFailure] = []

    for member in members {
      for name in node.dependentRequired[ExactText(member.key)] ?? []
        where !members.contains(where: { member in
          member.key.hasSameScalars(as: name)
        })
      {
        failures.append(failure(
          path,
          .dependentRequired,
          "\(AuthoredValue.quote(name)) is a dependency of \(AuthoredValue.quote(member.key))",
        ))
      }
    }

    return failures
  }

  private func propertyFailures(
    members: [AuthoredMember],
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    members.flatMap { member -> [SchemaFailure] in
      guard let index = node.properties[ExactText(member.key)] else {
        return []
      }

      return failures(
        of: member.value,
        at: path + [.key(member.key)],
        against: index,
      )
    }
  }

  private func additionalFailures(
    members: [AuthoredMember],
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    let unlisted = members.filter {
      node.properties[ExactText($0.key)] == nil
    }

    switch node.additionalProperties {
    case nil:
      return []
    case .forbidden:
      return unexpectedFailures(
        unlisted,
        at: path,
      )
    case let .schema(index):
      return unlisted.flatMap { member in
        failures(
          of: member.value,
          at: path + [.key(member.key)],
          against: index,
        )
      }
    }
  }

  private func unexpectedFailures(
    _ unlisted: [AuthoredMember],
    at path: [SchemaPathStep],
  ) -> [SchemaFailure] {
    guard !unlisted.isEmpty else {
      return []
    }

    let names = unlisted.map(\.key).map(AuthoredValue.quote).joined(separator: ", ")
    let verb = unlisted.count == 1 ? "was" : "were"

    return [failure(
      path,
      .additionalProperties,
      "Additional properties are not allowed (\(names) \(verb) unexpected)",
      members: unlisted.map(\.key),
    )]
  }

  /// A name that breaks `propertyNames` fails at the object, not at the name.
  private func nameFailures(
    members: [AuthoredMember],
    at path: [SchemaPathStep],
    node: SchemaNode,
  ) -> [SchemaFailure] {
    guard let index = node.propertyNames else {
      return []
    }

    var failures: [SchemaFailure] = []
    for member in members where !isValid(
      .string(member.key),
      against: index,
    ) {
      failures.append(failure(
        path,
        .propertyNames,
        "\(AuthoredValue.quote(member.key)) is not allowed",
      ))
    }

    return failures
  }
}
