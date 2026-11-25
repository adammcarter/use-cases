/// What `apply` is sent (chapter 16 §14, ADR 031): use cases to take out and whole use cases to
/// save, each use case at most once. The order the file lists them in is kept; the order they run
/// in is the planner's.
struct UseCaseBatch: Equatable, Sendable {
  /// The full ids to take out, as written.
  let removals: [String]

  /// The use cases to save, each held to the rules every definition file is held to.
  let saves: [CheckedUseCase]

  /// Refuses a batch that holds a use case more than once, removing and saving one included:
  /// that is an update, which is a save.
  func requireEachOnce() throws(UseCaseBatchError) {
    var seen: Set<[UInt8]> = []

    for identifier in removals + saves.map(\.identifier.text)
      where !seen.insert(Array(identifier.utf8)).inserted
    {
      throw .repeated(identifier: identifier)
    }
  }
}
