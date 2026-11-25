/// Resolves the groups of a file against the use cases of the workspace: include, then exclude,
/// which always wins (chapter 03 "Include / exclude resolution").
struct GroupResolver: GroupResolving {
  func resolve(
    _ file: GroupsFile,
    among known: KnownUseCases,
    in path: WorkspacePath,
  ) -> GroupsLoadResult {
    var found: [Diagnostic] = []
    var groups: [UseCaseGroup] = []

    if file.groups.isEmpty {
      found.append(.noGroups(in: path))
    }

    for definition in file.groups {
      let outcome = resolve(
        definition,
        among: known,
        in: path,
      )

      found += outcome.diagnostics
      groups += outcome.group.map { [$0] } ?? []
    }

    return GroupsLoadResult(
      groups: found.containsError ? [] : groups,
      diagnostics: found,
    )
  }

  private func resolve(
    _ definition: GroupDefinition,
    among known: KnownUseCases,
    in path: WorkspacePath,
  ) -> (group: UseCaseGroup?, diagnostics: [Diagnostic]) {
    let place = "groups/\(definition.name.text)"
    var found = structure(
      of: definition.include,
      at: place + "/include",
      isInclude: true,
      group: definition.name,
      in: path,
    )

    found += structure(
      of: definition.exclude,
      at: place + "/exclude",
      isInclude: false,
      group: definition.name,
      in: path,
    )

    guard case let .all(identifiers) = known, !found.containsError else {
      return (nil, found)
    }

    let selected = selectMembers(
      of: definition,
      among: identifiers,
      in: path,
    )

    found += selected.diagnostics

    guard !found.containsError else {
      return (nil, found)
    }

    let members = selected.members

    if members.isEmpty {
      found.append(.groupHasNoMembers(definition.name, in: path))
    }

    let group = UseCaseGroup(
      name: definition.name,
      description: definition.description,
      members: members.map(\.text).sorted { lhs, rhs in
        lhs.precedesExactly(rhs)
      },
    )

    return (group, found)
  }
}
