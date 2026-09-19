import Foundation

/// What the server reads off the process: the two mode switches, the configured
/// repo and the working directory a relative `repo` resolves against.
///
/// Passing it rather than reading `process.env` at each call is the seam the
/// tests drive; the values and their spellings are the TypeScript's.
public struct McpEnvironment: Sendable, Equatable {
  public let variables: [String: String]
  /// `process.cwd()`.
  public let workingDirectory: String

  public init(
    variables: [String: String],
    workingDirectory: String,
  ) {
    self.variables = variables
    self.workingDirectory = workingDirectory
  }

  /// The live process.
  public static var process: McpEnvironment {
    McpEnvironment(
      variables: ProcessInfo.processInfo.environment,
      workingDirectory: FileManager.default.currentDirectoryPath,
    )
  }

  /// `UCM_MCP_WRITE === "1"`. Nothing else enables writes, not even "true".
  public var isWriteModeEnabled: Bool {
    variables["UCM_MCP_WRITE"] == "1"
  }

  /// `UCM_MCP_COMMAND_EXECUTION === "1"`.
  public var isCommandExecutionEnabled: Bool {
    variables["UCM_MCP_COMMAND_EXECUTION"] == "1"
  }

  /// `UCM_MCP_REPO` when it is set and non-empty — the resource default repo
  /// and the root every resource repo must stay inside.
  public var configuredRepository: String? {
    guard let value = variables["UCM_MCP_REPO"], !value.isEmpty else {
      return nil
    }
    return value
  }
}
