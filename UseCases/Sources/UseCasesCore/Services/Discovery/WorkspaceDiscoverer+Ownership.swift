extension WorkspaceDiscoverer {
  /// The rules that give every definition exactly one owner (chapter 04, "Scope ownership"): no
  /// scope, nested workspace included, inside another scope's `use_cases_dir`, and no two
  /// `use_cases_dir`s the same or one inside the other.
  func ownershipDiagnostics(
    settings: [WorkspacePath: ScopeSettings],
    scopeDirectories: Set<WorkspacePath>,
  ) -> [Diagnostic] {
    var diagnostics: [Diagnostic] = []

    for (owner, ownerSettings) in settings {
      let definitions = owner.joining(ownerSettings.useCasesDirectory)

      for other in scopeDirectories where other != owner && other.isInsideOrEqual(to: definitions) {
        diagnostics.append(
          .scopeInsideDefinitions(
            other.appending(literal: DiscoveredScope.configurationFileName),
            definitions: definitions,
            owner: owner,
          ),
        )
      }
    }

    return diagnostics + overlapDiagnostics(settings: settings)
  }

  /// A `use_cases_dir` that is, or lies inside, another scope's, where the scope's folder is not
  /// itself inside that `use_cases_dir` (that case is reported above). When two are the same
  /// folder, the scope that sorts later is the one reported.
  private func overlapDiagnostics(settings: [WorkspacePath: ScopeSettings]) -> [Diagnostic] {
    var diagnostics: [Diagnostic] = []

    for (scope, scopeSettings) in settings {
      let definitions = scope.joining(scopeSettings.useCasesDirectory)

      for (other, otherSettings) in settings where other != scope {
        let otherDefinitions = other.joining(otherSettings.useCasesDirectory)

        guard
          definitions.isInsideOrEqual(to: otherDefinitions),
          !scope.isInsideOrEqual(to: otherDefinitions),
          definitions != otherDefinitions || scope > other
        else {
          continue
        }

        diagnostics.append(
          .definitionsOverlap(
            scope.appending(literal: DiscoveredScope.configurationFileName),
            definitions: definitions,
            other: other,
            otherDefinitions: otherDefinitions,
          ),
        )
      }
    }

    return diagnostics
  }
}
