extension LinkConflictFinder {
  /// Where links of one use case, one role and one file cover some of the same bytes. The role
  /// is the route: implementation links have none. A span with no bytes overlaps nothing. Each
  /// overlapping pair is one warning.
  func overlaps(among links: [ResolvedLink]) -> [Diagnostic] {
    var found: [Diagnostic] = []

    let groups = Dictionary(grouping: links) { link in
      OverlapGroup(
        identity: link.identity.useCase,
        route: link.identity.route,
        file: link.path,
      )
    }

    for group in groups.values where group.count > 1 {
      found += overlaps(inGroup: group)
    }

    return found
  }

  /// The pairs in a group, found by sweeping the spans in order of where they start.
  private func overlaps(inGroup group: [ResolvedLink]) -> [Diagnostic] {
    let ordered = group
      .filter { link in
        !link.span.isEmpty
      }
      .sorted { lhs, rhs in
        lhs.span.lowerBound != rhs.span.lowerBound
          ? lhs.span.lowerBound < rhs.span.lowerBound
          : lhs.precedes(rhs)
      }

    var found: [Diagnostic] = []
    var active: [ResolvedLink] = []

    for link in ordered {
      active.removeAll { earlier in
        earlier.span.upperBound <= link.span.lowerBound
      }

      for earlier in active {
        found.append(.overlappingLinks(earlier, link))
      }

      active.append(link)
    }

    return found
  }
}

/// The links that can overlap: one use case, one role and one file.
private struct OverlapGroup: Hashable {
  let identity: UseCaseIdentifier
  let route: RouteIdentifier?
  let file: WorkspacePath
}
