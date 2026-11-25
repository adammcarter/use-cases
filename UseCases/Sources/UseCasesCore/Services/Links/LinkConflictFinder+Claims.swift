extension LinkConflictFinder {
  /// The bindings that more than one source names: a manual binding, markers in the code, a links
  /// transformer. Many marker regions, or many links of one transformer, under one identity are
  /// fine; a second source is not.
  func claimedTwice(
    _ links: [ResolvedLink],
    definitions: [UseCaseIdentifier: WorkspacePath],
  ) -> [ClaimedBinding] {
    var claims: [ClaimedBinding] = []

    for (identity, group) in Dictionary(grouping: links, by: \.identity) {
      let sources = Dictionary(grouping: group, by: \.source)

      guard sources.count > 1 else {
        continue
      }

      claims.append(
        ClaimedBinding(
          identity: identity,
          diagnostic: .bindingClaimedTwice(
            identity,
            manual: sources[.manual]?.first,
            markers: sources[.marker] ?? [],
            transformed: sources[.transformer] ?? [],
            definedIn: definitions[identity.useCase] ?? group[0].path,
          ),
        ),
      )
    }

    return claims
  }
}
