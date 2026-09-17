/// One command step handed to the spawner: node's
/// `spawnSync(file, args, { cwd, env, timeout, maxBuffer, shell: false })`.
public struct CapsuleSpawnRequest: Sendable, Equatable {
  public let executable: String
  public let arguments: [String]
  public let workingDirectory: String
  /// `NAME=value` entries, in the order the child's `environ` holds them.
  public let environment: [String]
  public let timeoutMilliseconds: Double

  public init(
    executable: String,
    arguments: [String],
    workingDirectory: String,
    environment: [String],
    timeoutMilliseconds: Double,
  ) {
    self.executable = executable
    self.arguments = arguments
    self.workingDirectory = workingDirectory
    self.environment = environment
    self.timeoutMilliseconds = timeoutMilliseconds
  }
}
