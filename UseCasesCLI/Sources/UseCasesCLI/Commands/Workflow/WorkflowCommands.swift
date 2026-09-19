import UseCasesCore

/// `workflow set-mode` and `workflow mode`
/// (packages/cli/src/commands/workflow.ts). The mode is advisory and lives in
/// the workspace's `use-cases.yml`; a workspace without one is a thrown read
/// failure, as in the TypeScript.
enum WorkflowCommands {
  static let all = [setMode, mode]

  static let setMode = CommandSpecification(
    path: ["workflow", "set-mode"],
    command: "workflow.set-mode",
    summary: "Persist the advisory workflow mode.",
    flags: CommonFlags.workspace + [
      FlagSpecification(
        key: "mode",
        name: "--mode",
        kind: .string,
        summary: "Advisory workflow mode.",
        valueName: "<mode>",
      ),
    ],
  ) { context throws(CommandFailure) in
    let command = "workflow.set-mode"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let requestedValue = ArgumentScanner.value(after: "--mode", in: context.arguments)
    guard let requested = WorkflowModeFile.canonicalMode(requestedValue) else {
      return CommandOutput(
        result: ErrorEnvelope.make(
          command: command,
          code: "workflow_mode_invalid",
          message: "Unsupported workflow mode.",
        ),
        exitCode: 2,
      )
    }

    let path = configurationPath(workspace)
    let previous = try WorkflowModeFile.mode(in: readConfiguration(atPath: path))
    let isChanged = previous != requested
    if isChanged {
      try writeMode(requested, atPath: path)
    }

    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("previous_mode", .string(previous)),
      ("configured_mode", .string(requested)),
      ("effective_mode", .string(requested)),
      ("source", .string("workspace_config")),
      ("advisory", .bool(true)),
      ("changed", .bool(isChanged)),
    ]))
    return output(command: command, data: data, workspace: workspace)
  }

  static let mode = CommandSpecification(
    path: ["workflow", "mode"],
    command: "workflow.get-mode",
    summary: "Print the effective advisory workflow mode.",
    flags: CommonFlags.workspace,
  ) { context throws(CommandFailure) in
    let command = "workflow.get-mode"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let effective = try WorkflowModeFile.mode(
      in: readConfiguration(atPath: configurationPath(workspace)),
    )
    let source = effective == WorkflowModeFile.defaultMode
      ? "default_or_config"
      : "workspace_config"
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("effective_mode", .string(effective)),
      ("source", .string(source)),
      ("advisory", .bool(true)),
    ]))
    return output(command: command, data: data, workspace: workspace)
  }

  private static func configurationPath(_ workspace: ResolvedWorkspaceContext) -> String {
    WorkspacePath.absolute("use-cases.yml", relativeTo: workspace.workspaceRoot)
  }

  private static func readConfiguration(atPath path: String) throws(CommandFailure) -> String {
    do {
      return try NodeFile.readText(atPath: path)
    } catch {
      throw CommandFailure(error)
    }
  }

  /// Written to a sibling temporary file, then renamed over the config.
  private static func writeMode(
    _ mode: String,
    atPath path: String,
  ) throws(CommandFailure) {
    let source = try readConfiguration(atPath: path)
    let temporaryPath = path + ".tmp"
    do {
      try NodeFile.writeText(
        WorkflowModeFile.replacingMode(in: source, with: mode),
        atPath: temporaryPath,
      )
      try NodeFile.rename(from: temporaryPath, to: path)
    } catch {
      throw CommandFailure(error)
    }
  }

  private static func output(
    command: String,
    data: JSONValue,
    workspace: ResolvedWorkspaceContext,
  ) -> CommandOutput {
    CommandOutput(
      result: CliResult.make(
        command: command,
        data: data,
        workspaceRoot: workspace.workspaceRoot,
        dataRoot: workspace.dataRoot,
        componentIdentifier: workspace.componentIdentifier,
      ),
      exitCode: 0,
    )
  }
}
