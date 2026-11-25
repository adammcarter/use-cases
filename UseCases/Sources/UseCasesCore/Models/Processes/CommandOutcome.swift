/// What a program run through ``CommandRunning`` did: how it ended and everything it printed.
public struct CommandOutcome: Equatable, Sendable {
  /// How it ended.
  public let ending: CommandEnding

  /// Everything it wrote to stdout, whole however large, decoded as UTF-8 with U+FFFD for each
  /// invalid sequence.
  public let standardOutput: String

  /// Everything it wrote to stderr, in the same way.
  public let standardError: String

  /// Describes how a program ended and what it printed.
  public init(
    ending: CommandEnding,
    standardOutput: String,
    standardError: String,
  ) {
    self.ending = ending
    self.standardOutput = standardOutput
    self.standardError = standardError
  }
}
