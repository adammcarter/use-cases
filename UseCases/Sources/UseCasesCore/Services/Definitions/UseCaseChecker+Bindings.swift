extension UseCaseChecker {
  /// Binding ids are unique within the use case and within each route, and a manual range does
  /// not start after it ends (chapter 08 "Binding ID uniqueness" and "Manual binding validity").
  /// Whether a range fits its file is checked against the file, later.
  func checkBindings(
    of useCase: UseCaseDefinition,
    named name: String,
    findings: inout AuthoredFindings,
  ) {
    checkBindings(
      useCase.bindings,
      ownedBy: name,
      findings: &findings,
    )

    for route in useCase.routes {
      let owner = "validation route \(AuthoredValue.quote(route.identifier.text)) of \(name)"
      checkBindings(
        route.bindings,
        ownedBy: owner,
        findings: &findings,
      )
    }
  }

  private func checkBindings(
    _ bindings: [ManualBinding],
    ownedBy owner: String,
    findings: inout AuthoredFindings,
  ) {
    for text in Self.repeated(bindings.map(\.identifier.text)) {
      findings.add(
        .duplicateBinding,
        "\(owner) has two bindings with id \(AuthoredValue.quote(text))",
      )
    }

    for binding in bindings {
      guard let range = binding.locator.range, range.startsAfterEnd else {
        continue
      }

      let start = Self.describe(range.start)
      let end = Self.describe(range.end)
      findings.add(
        .malformedRange,
        "binding \(AuthoredValue.quote(binding.identifier.text)) of \(owner) has a range "
          + "that starts after it ends (\(start) to \(end))",
      )
    }
  }

  private static func describe(_ position: SourcePosition) -> String {
    guard let column = position.column else {
      return "line \(position.line)"
    }

    return "line \(position.line), column \(column)"
  }
}
