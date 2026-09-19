/// What `spawnSync` returned for one command step.
public struct CapsuleSpawnOutcome: Sendable, Equatable {
  /// `status`: nil when the program never started or a signal ended it.
  public let exitStatus: Int?
  /// `signal`: the name of the signal that ended the program.
  public let signal: String?
  /// `stdout`: nil when the program never started.
  public let standardOutput: String?
  /// `stderr`: nil when the program never started.
  public let standardError: String?
  /// `error.message`, e.g. `spawnSync ./tool ENOENT`, when the program never
  /// started.
  public let errorMessage: String?

  public init(
    exitStatus: Int?,
    signal: String?,
    standardOutput: String?,
    standardError: String?,
    errorMessage: String?,
  ) {
    self.exitStatus = exitStatus
    self.signal = signal
    self.standardOutput = standardOutput
    self.standardError = standardError
    self.errorMessage = errorMessage
  }
}
