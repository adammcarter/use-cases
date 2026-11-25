/// What the results store holds (chapter 16 §9): how many runs, how much space they take, and
/// how many of them `prune` would remove.
public struct StoreSummary: Equatable, Sendable {
  /// Every run folder, sealed or not.
  public let runs: Int

  /// The size of every file under `.use-cases/`, in bytes.
  public let bytes: Int64

  /// The sealed runs a later run has said everything again for (chapter 12 §31).
  public let superseded: Int

  public init(
    runs: Int,
    bytes: Int64,
    superseded: Int,
  ) {
    self.runs = runs
    self.bytes = bytes
    self.superseded = superseded
  }
}
