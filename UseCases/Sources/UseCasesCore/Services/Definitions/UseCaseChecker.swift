struct UseCaseChecker: UseCaseChecking {
  func check(
    _ useCase: UseCaseDefinition,
    file: WorkspacePath,
  ) -> [Diagnostic] {
    var findings = AuthoredFindings(file: file)
    let name = "use case \(AuthoredValue.quote(useCase.localIdentifier.text))"

    for text in Self.repeated(useCase.scenarios.map(\.identifier.text)) {
      findings.add(
        .duplicateScenario,
        "\(name) has two scenarios with id \(AuthoredValue.quote(text))",
      )
    }

    for text in Self.repeated(useCase.routes.map(\.identifier.text)) {
      findings.add(
        .duplicateRoute,
        "\(name) has two routes with id \(AuthoredValue.quote(text))",
      )
    }

    checkCoverage(
      of: useCase,
      named: name,
      findings: &findings,
    )
    checkBindings(
      of: useCase,
      named: name,
      findings: &findings,
    )

    return findings.sorted
  }

  /// Each text that appears more than once, once, in the order it first appears.
  static func repeated(_ texts: [String]) -> [String] {
    var seen: Set<String> = []
    var reported: Set<String> = []
    var repeated: [String] = []

    for text in texts {
      if !seen.insert(text).inserted, reported.insert(text).inserted {
        repeated.append(text)
      }
    }

    return repeated
  }

  private func checkCoverage(
    of useCase: UseCaseDefinition,
    named name: String,
    findings: inout AuthoredFindings,
  ) {
    let known = Set(useCase.scenarios.map(\.identifier))

    for route in useCase.routes {
      let unknown = route.covers.filter { identifier in
        !known.contains(identifier)
      }

      guard !unknown.isEmpty else {
        continue
      }

      let route = AuthoredValue.quote(route.identifier.text)
      findings.add(
        .unknownScenario,
        "validation route \(route) of \(name) covers unknown scenarios "
          + Self.list(unknown.map(\.text)),
      )
    }
  }

  /// The texts as a list in single quotes: `['a', 'b']`.
  private static func list(_ texts: [String]) -> String {
    let quoted = texts.map { text in
      AuthoredValue.quote(text)
    }

    return "[" + quoted.joined(separator: ", ") + "]"
  }
}
