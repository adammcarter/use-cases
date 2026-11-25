/// Turns the resolved links of one collection into the bindings a route fingerprints (chapter 11
/// §33, §89.5).
protocol LinkContributionBuilding: Sendable {
  /// One contribution per binding id among `links`, each holding one region per link, read from
  /// the real bytes of the file it points into.
  ///
  /// A file that cannot be read, or a region that no longer fits its file, is a diagnostic and
  /// leaves that binding out: the answer is then unusable, never partial.
  func contributions(
    of links: [ResolvedLink],
    in run: FreshnessRun,
    caches: inout FreshnessCaches,
  ) -> LinkContributions
}
