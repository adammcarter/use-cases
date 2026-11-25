/// What `prune` did: the runs and leftovers it removed, the planned runs it kept, the runs it took
/// out of the store and could not delete, and a note for each that is not simply removed.
public struct PruneOutcome: Equatable, Sendable {
  public let removed: [PrunableRun]
  public let leftovers: [PruneLeftover]

  /// Planned runs still in the store: held by another process, or refused by the file system.
  public let kept: [PrunableRun]

  /// Runs taken out of `runs/` whose folder could not be deleted: left over for the next prune.
  /// Their space is not freed.
  public let leftOver: [PruneLeftover]

  /// Why each kept or left-over run is where it is.
  public let notes: [String]

  public init(
    removed: [PrunableRun],
    leftovers: [PruneLeftover] = [],
    kept: [PrunableRun] = [],
    leftOver: [PruneLeftover] = [],
    notes: [String],
  ) {
    self.removed = removed
    self.leftovers = leftovers
    self.kept = kept
    self.leftOver = leftOver
    self.notes = notes
  }
}
