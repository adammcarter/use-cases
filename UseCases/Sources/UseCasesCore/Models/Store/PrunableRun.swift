/// A sealed run `prune` removes, and the space its folder takes.
public struct PrunableRun: Equatable, Sendable {
  /// The whole 32-digit run id.
  public let identifier: String

  /// The size of every file in the run's folder, in bytes.
  public let bytes: Int64

  public init(
    identifier: String,
    bytes: Int64,
  ) {
    self.identifier = identifier
    self.bytes = bytes
  }
}
