/// The run `use-cases verify --abort` closed (chapter 13 §6).
public struct AbortedVerifyRun: Equatable, Sendable {
  /// The run's id.
  public let runIdentifier: String

  /// Makes a description of an aborted run.
  public init(runIdentifier: String) {
    self.runIdentifier = runIdentifier
  }
}
