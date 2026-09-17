import Foundation

/// The CLI entry dispatcher (packages/cli/src/index.ts `runCli`).
///
/// Help and version win wherever they appear, so `matrix upsert --help` is
/// scoped help rather than a run. A registry command is checked for unknown
/// flags (exit 2) and then dispatched; anything else goes to the builtins.
public enum CommandLineInterface {
  /// Run one invocation, given the arguments after the program name.
  ///
  /// `environment` is what the TypeScript reads as `process.env`: what child
  /// processes run with, the run key's location, signing keys and CI identity.
  public static func run(
    arguments: [String],
    environment: [String: String] = ProcessInfo.processInfo.environment,
  ) async -> CliOutcome {
    let normalized = normalized(arguments)
    let isJSON = normalized.contains("--json")

    if isHelpOrVersion(normalized) {
      return BuiltinCommands.run(arguments: arguments, environment: environment)
    }
    guard let command = CommandMatcher.match(normalized, in: CommandRegistry.allCommands) else {
      return BuiltinCommands.run(arguments: arguments, environment: environment)
    }

    let unknown = UnknownFlagFinder.unknownFlags(
      in: normalized,
      commands: CommandRegistry.allCommands,
    )
    guard unknown.isEmpty else {
      let noun = unknown.count > 1 ? "options" : "option"
      let result = ErrorEnvelope.make(
        command: command.command,
        code: "cli_unknown_flag",
        message: "Unknown \(noun): \(unknown.joined(separator: ", "))",
      )
      return CliOutcome(
        standardOutput: EnvelopeRenderer.render(result.jsonValue(), isJSON: isJSON),
        exitCode: 2,
      )
    }
    return await CommandDispatcher.run(
      command,
      arguments: normalized,
      isJSON: isJSON,
      environment: environment,
    )
  }

  /// One leading `--` is dropped, as a package runner may pass one through.
  static func normalized(_ arguments: [String]) -> [String] {
    arguments.first == "--" ? Array(arguments.dropFirst()) : arguments
  }

  private static func isHelpOrVersion(_ arguments: [String]) -> Bool {
    arguments.isEmpty
      || arguments.contains("--help")
      || arguments.contains("-h")
      || arguments.contains("--version")
      || arguments.contains("-v")
      || arguments.first == "version"
  }
}
