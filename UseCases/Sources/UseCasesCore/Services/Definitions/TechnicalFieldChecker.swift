struct TechnicalFieldChecker: TechnicalFieldChecking {
  /// The fields chapter 06 ("Where running lives") and the acceptance suite name as belonging
  /// to the bridge settings. No chapter closes the list.
  static let technicalFields = [
    "runner", "command", "arguments", "environment", "timeout", "retries", "parallel", "batch",
  ]

  func check(
    _ value: AuthoredValue,
    file: WorkspacePath,
  ) -> [Diagnostic] {
    var findings = AuthoredFindings(file: file)

    guard
      case let .object(members) = value,
      case let .array(useCases)? = Self.value(for: "use_cases", in: members)
    else {
      return []
    }

    for (index, useCase) in useCases.enumerated() {
      guard case let .object(useCaseMembers) = useCase else {
        continue
      }

      let name = Self.name(
        of: useCaseMembers,
        called: "use case",
        number: index + 1,
      )
      report(
        fieldsIn: useCaseMembers,
        of: name,
        findings: &findings,
        refusedIn: "a use case",
      )

      guard case let .array(routes)? = Self.value(for: "validation", in: useCaseMembers) else {
        continue
      }

      for (routeIndex, route) in routes.enumerated() {
        guard case let .object(routeMembers) = route else {
          continue
        }

        let routeName = Self.name(
          of: routeMembers,
          called: "validation route",
          number: routeIndex + 1,
        )
        report(
          fieldsIn: routeMembers,
          of: "\(routeName) of \(name)",
          findings: &findings,
          refusedIn: "a validation route",
        )
      }
    }

    return findings.sorted
  }

  private func report(
    fieldsIn members: [AuthoredMember],
    of owner: String,
    findings: inout AuthoredFindings,
    refusedIn place: String,
  ) {
    for member in members where Self.isTechnical(member.key) {
      findings.add(
        .technicalField,
        "\(owner) writes `\(member.key)`, which names code or tools; "
          + "say it in use-cases-bridge.yml, not in \(place)",
      )
    }
  }

  private static func isTechnical(_ key: String) -> Bool {
    technicalFields.contains { field in
      field.isExactlyEqual(to: key)
    }
  }

  private static func value(
    for key: String,
    in members: [AuthoredMember],
  ) -> AuthoredValue? {
    members.first { member in
      member.key.isExactlyEqual(to: key)
    }?.value
  }

  /// `use case 'login'`, or its place in the list when it has no readable id.
  private static func name(
    of members: [AuthoredMember],
    called kind: String,
    number: Int,
  ) -> String {
    guard case let .string(text)? = value(for: "id", in: members) else {
      return "\(kind) number \(number)"
    }

    return "\(kind) \(AuthoredValue.quote(text))"
  }
}
