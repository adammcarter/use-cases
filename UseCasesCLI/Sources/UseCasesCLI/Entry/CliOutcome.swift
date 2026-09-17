/// Everything one invocation produced: the bytes for each stream and the exit
/// code. The TypeScript writes each stream once, at the end, so buffering them
/// here changes nothing observable.
public struct CliOutcome: Sendable, Equatable {
  /// The bytes for standard output.
  public let standardOutput: String

  /// The bytes for standard error.
  public let standardError: String

  /// The process exit code.
  public let exitCode: Int32

  init(
    standardOutput: String,
    standardError: String = "",
    exitCode: Int32,
  ) {
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.exitCode = exitCode
  }
}
