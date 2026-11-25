/// Finds conflicts among links by grouping them: by binding, by key and by file.
struct LinkConflictFinder: LinkConflictFinding {
  func conflicts(
    among links: [ResolvedLink],
    definitions: [UseCaseIdentifier: WorkspacePath],
  ) -> [Diagnostic] {
    let claims = claimedTwice(
      links,
      definitions: definitions,
    )
    let claimed = Set(claims.map(\.identity))
    let unclaimed = links.filter { link in
      !claimed.contains(link.identity)
    }

    return claims.map(\.diagnostic) + sharedKeys(among: unclaimed) + overlaps(among: links)
  }
}
