extension GroupResolver {
  /// The use cases some selectors choose, with the problems and warnings of choosing them.
  struct Selection {
    let chosen: Set<Namespace>
    let diagnostics: [Diagnostic]
  }

  /// What a selector object says by itself, whatever the use cases are: nothing to select with,
  /// empty lists, and the same selector twice.
  func structure(
    of selectors: GroupSelectors?,
    at place: String,
    isInclude: Bool,
    group: IdentifierSegment,
    in path: WorkspacePath,
  ) -> [Diagnostic] {
    guard let selectors else {
      return []
    }

    guard !selectors.selectsNothing else {
      return emptyDiagnostics(
        of: selectors,
        at: place,
        isInclude: isInclude,
        group: group,
        in: path,
      )
    }

    return duplicates(
      among: selectors.ids.map(\.text),
      at: place + "/ids",
      in: path,
    ) + duplicates(
      among: selectors.prefixes.map(\.text),
      at: place + "/prefixes",
      in: path,
    ) + duplicates(
      among: selectors.globs.map(\.text),
      at: place + "/globs",
      in: path,
    ) + emptyLists(
      of: selectors,
      at: place,
      in: path,
    )
  }

  /// The use cases a group holds: what `include` chooses, or every use case without one, less what
  /// `exclude` chooses.
  func selectMembers(
    of definition: GroupDefinition,
    among identifiers: [UseCaseIdentifier],
    in path: WorkspacePath,
  ) -> (members: Set<Namespace>, diagnostics: [Diagnostic]) {
    let place = "groups/\(definition.name.text)"
    let existing = Set(identifiers.map(\.namespace))
    let included = definition.include.map { selectors in
      select(
        selectors,
        at: place + "/include",
        among: identifiers,
        existing: existing,
        in: path,
      )
    }
    let excluded = definition.exclude.map { selectors in
      select(
        selectors,
        at: place + "/exclude",
        among: identifiers,
        existing: existing,
        in: path,
      )
    }

    return (
      (included?.chosen ?? existing).subtracting(excluded?.chosen ?? []),
      (included?.diagnostics ?? []) + (excluded?.diagnostics ?? []),
    )
  }

  /// Chooses the use cases the selectors fit.
  func select(
    _ selectors: GroupSelectors,
    at place: String,
    among identifiers: [UseCaseIdentifier],
    existing: Set<Namespace>,
    in path: WorkspacePath,
  ) -> Selection {
    var chosen: Set<Namespace> = []
    var found: [Diagnostic] = []

    for (index, namespace) in selectors.ids.enumerated() {
      if existing.contains(namespace) {
        chosen.insert(namespace)
      } else {
        found.append(
          .noSuchUseCase(
            namespace,
            at: "\(place)/ids/\(index)",
            in: path,
          ),
        )
      }
    }

    for (index, prefix) in selectors.prefixes.enumerated() {
      let matched = identifiers.filter { identifier in
        identifier.namespace.segments.starts(with: prefix.segments)
      }

      chosen.formUnion(matched.map(\.namespace))

      if matched.isEmpty {
        found.append(
          .selectorMatchesNothing(
            "prefix",
            prefix.text,
            at: "\(place)/prefixes/\(index)",
            in: path,
          ),
        )
      }
    }

    for (index, glob) in selectors.globs.enumerated() {
      let matched = identifiers.filter(glob.matches)

      chosen.formUnion(matched.map(\.namespace))

      if matched.isEmpty {
        found.append(
          .selectorMatchesNothing(
            "glob",
            glob.text,
            at: "\(place)/globs/\(index)",
            in: path,
          ),
        )
      }
    }

    return Selection(
      chosen: chosen,
      diagnostics: found,
    )
  }

  private func emptyDiagnostics(
    of selectors: GroupSelectors,
    at place: String,
    isInclude: Bool,
    group: IdentifierSegment,
    in path: WorkspacePath,
  ) -> [Diagnostic] {
    if isInclude {
      return [.includeSelectsNothing(group: group, in: path)]
    }

    // An exclude of `{}` excludes nothing; one that writes only empty lists says so list by list.
    guard selectors.written.isEmpty else {
      return emptyLists(
        of: selectors,
        at: place,
        in: path,
      )
    }

    return [.emptySelectors(at: place, in: path)]
  }

  private func emptyLists(
    of selectors: GroupSelectors,
    at place: String,
    in path: WorkspacePath,
  ) -> [Diagnostic] {
    let empty = GroupSelectorKind.allCases.filter { kind in
      selectors.written.contains(kind) && selectors.writesNothing(in: kind)
    }

    return empty.map { kind in
      .emptySelectorList(
        at: "\(place)/\(kind.rawValue)",
        in: path,
      )
    }
  }

  private func duplicates(
    among selectors: [String],
    at place: String,
    in path: WorkspacePath,
  ) -> [Diagnostic] {
    var seen: Set<String> = []
    var found: [Diagnostic] = []

    for (index, selector) in selectors.enumerated() {
      // The first of a selector is fine; each repeat is the warning.
      if seen.insert(selector).inserted {
        continue
      }

      found.append(
        .duplicateSelector(
          selector,
          at: "\(place)/\(index)",
          in: path,
        ),
      )
    }

    return found
  }
}
