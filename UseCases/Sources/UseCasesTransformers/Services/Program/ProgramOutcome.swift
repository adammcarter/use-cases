/// How a run of the program ended.
public struct ProgramOutcome: Equatable, Sendable {
  /// The process exit code: 0 when the response was written.
  public let exitCode: Int32
  /// What to print on stderr, nil when all went well.
  public let message: String?
}
