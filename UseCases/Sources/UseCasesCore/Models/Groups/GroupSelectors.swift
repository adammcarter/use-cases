/// What `include` or `exclude` of a group selects (chapter 03): whole use case ids, id prefixes
/// and globs, each as written and in the order written.
struct GroupSelectors: Equatable, Sendable {
  let ids: [Namespace]
  let prefixes: [Namespace]
  let globs: [IdentifierGlob]

  /// The lists the file writes at all, empty ones included.
  let written: Set<GroupSelectorKind>

  /// Whether nothing at all is written to select with.
  var selectsNothing: Bool {
    ids.isEmpty && prefixes.isEmpty && globs.isEmpty
  }

  /// Whether the list of this kind holds nothing.
  func writesNothing(in kind: GroupSelectorKind) -> Bool {
    switch kind {
    case .ids:
      ids.isEmpty
    case .prefixes:
      prefixes.isEmpty
    case .globs:
      globs.isEmpty
    }
  }
}
