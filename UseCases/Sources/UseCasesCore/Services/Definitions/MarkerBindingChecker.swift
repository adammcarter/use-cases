struct MarkerBindingChecker: MarkerBindingChecking {
  func check(
    _ value: AuthoredValue,
    file: WorkspacePath,
  ) -> MarkerBindingFindings {
    var findings = MarkerBindingFindings()

    guard
      case let .object(members) = value,
      case let .array(useCases)? = members.value(for: "use_cases")
    else {
      return findings
    }

    for (index, useCase) in useCases.enumerated() {
      guard case let .object(useCaseMembers) = useCase else {
        continue
      }

      let owner = "use case \(useCaseMembers.name(number: index + 1))"
      let path: [SchemaPathStep] = [.key("use_cases"), .index(index)]

      check(
        bindingsOf: useCaseMembers,
        ownedBy: owner,
        at: path,
        file: file,
        findings: &findings,
      )

      guard case let .array(routes)? = useCaseMembers.value(for: "validation") else {
        continue
      }

      for (routeIndex, route) in routes.enumerated() {
        guard case let .object(routeMembers) = route else {
          continue
        }

        check(
          bindingsOf: routeMembers,
          ownedBy: "route \(routeMembers.name(number: routeIndex + 1)) of \(owner)",
          at: path + [.key("validation"), .index(routeIndex)],
          file: file,
          findings: &findings,
        )
      }
    }

    return findings
  }

  private func check(
    bindingsOf members: [AuthoredMember],
    ownedBy owner: String,
    at path: [SchemaPathStep],
    file: WorkspacePath,
    findings: inout MarkerBindingFindings,
  ) {
    guard case let .array(bindings)? = members.value(for: "bindings") else {
      return
    }

    for (index, binding) in bindings.enumerated() {
      guard
        case let .object(bindingMembers) = binding,
        case let .string(kind)? = bindingMembers.value(for: "kind"),
        kind.isExactlyEqual(to: "marker")
      else {
        continue
      }

      findings.bindingPaths.append(path + [.key("bindings"), .index(index)])
      findings.diagnostics.append(
        Diagnostic(
          error: .markerBindingInYAML,
          in: file,
          message: "binding \(bindingMembers.name(number: index + 1)) of \(owner) is "
            + "kind: marker; marker bindings need no entry in the YAML: the marker in the code "
            + "is the binding",
        ),
      )
    }
  }
}

private extension [AuthoredMember] {
  /// The value of the member with exactly this key.
  func value(for key: String) -> AuthoredValue? {
    first { member in
      member.key.isExactlyEqual(to: key)
    }?.value
  }

  /// The quoted `id` of an item, or its place in its list when it has no readable id.
  func name(number: Int) -> String {
    guard case let .string(text)? = value(for: "id") else {
      return "number \(number)"
    }

    return AuthoredValue.quote(text)
  }
}
