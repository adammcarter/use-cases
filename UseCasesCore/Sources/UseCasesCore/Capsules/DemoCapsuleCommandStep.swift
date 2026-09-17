/// A runbook step that runs a program (`DemoCapsuleCommandStep`).
public struct DemoCapsuleCommandStep: Sendable, Equatable {
  public let executable: String
  public let arguments: [String]
  /// As the capsule spells it: relative to the workspace, absolute, or empty.
  public let workingDirectory: String
  /// Whole numbers, as the schema requires; doubles because JSON carries them
  /// so.
  public let expectedExitCodes: [Double]

  public init(
    executable: String,
    arguments: [String],
    workingDirectory: String,
    expectedExitCodes: [Double],
  ) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.expectedExitCodes = expectedExitCodes
  }
}
