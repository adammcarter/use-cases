/// What an interrupted `prune` left behind: a run's folder already moved out of `runs/`, to
/// `.tmp-prune-<id>`, whose bytes were never deleted (chapter 12 §31). It is no run any more, and
/// prune removes it.
public struct PruneLeftover: Equatable, Sendable {
  /// Where it is, relative to the workspace root: `.use-cases/runs/.tmp-prune-<id>`.
  public let location: String

  /// The size of every file in it, in bytes.
  public let bytes: Int64

  public init(
    location: String,
    bytes: Int64,
  ) {
    self.location = location
    self.bytes = bytes
  }
}
