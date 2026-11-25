extension LinkConflictFinder {
  /// The link keys that more than one link has.
  func sharedKeys(among links: [ResolvedLink]) -> [Diagnostic] {
    var found: [Diagnostic] = []

    for (key, group) in Dictionary(grouping: links, by: \.key) where group.count > 1 {
      guard let first = group.inLinkOrder.first else {
        continue
      }

      found.append(
        .linkKeyShared(
          key,
          first: first,
          count: group.count,
        ),
      )
    }

    return found
  }
}
