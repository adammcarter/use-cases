/// Resolves the resources of a route to the files they name (chapter 09 §20.2, chapter 11 §42).
protocol ResourceResolving: Sendable {
  /// The files `resources` name, each once, and every declaration that names nothing usable.
  ///
  /// An explicit file must be there exactly as spelled, and may be in an excluded folder. A
  /// glob matches only among `scanned`, the files the code scan reads, and a glob that matches
  /// none of them is a problem.
  func resolve(
    _ resources: [RouteResource],
    among scanned: [WorkspacePath],
    in context: DiscoveryContext,
    listings: inout FolderListings,
  ) -> ResolvedResources
}
