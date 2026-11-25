/// What `prune` would remove (chapter 12 §31): every superseded sealed run, oldest first, and
/// every folder an interrupted prune left behind.
public struct PrunePlan: Equatable, Sendable {
  public let runs: [PrunableRun]
  public let leftovers: [PruneLeftover]

  public init(
    runs: [PrunableRun],
    leftovers: [PruneLeftover] = [],
  ) {
    self.runs = runs
    self.leftovers = leftovers
  }

  /// Whether there is nothing to remove.
  public var isEmpty: Bool {
    runs.isEmpty && leftovers.isEmpty
  }
}
