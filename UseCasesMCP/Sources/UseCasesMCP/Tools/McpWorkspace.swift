import UseCasesCore

/// The workspace a tool call runs against (packages/mcp/src/toolHandlers.ts
/// `contextFromArgs`).
///
/// Unlike the CLI, `repo` is mandatory: there is no working directory an agent
/// could mean. `data_root` resolves against the REPO here, not the working
/// directory, and must stay inside it.
public enum McpWorkspace {
  public enum Resolution {
    case resolved(ResolvedWorkspaceContext)
    case refused(CliResult)
  }

  public static func resolve(
    arguments: JSONObject,
    command: String,
    environment: McpEnvironment,
  ) throws(McpToolFailure) -> Resolution {
    guard let repository = McpToolArguments.string(arguments, "repo") else {
      return .refused(McpErrorEnvelope.make(
        command: command,
        code: "mcp.repo_required",
        message: "MCP workspace tools require repo.",
        environment: environment,
      ))
    }
    let workspaceRoot = WorkspacePath.absolute(
      repository,
      relativeTo: environment.workingDirectory,
    )
    // The shared core guard: a repo that is not there is a typo, not a valid
    // empty workspace. The CLI applies the same one, so both transports emit an
    // identical workspace.not_found envelope.
    if let missing = WorkspaceContextResolver.workspaceNotFoundDiagnostic(
      workspaceRoot: workspaceRoot,
    ) {
      return .refused(McpErrorEnvelope.make(
        command: command,
        code: missing.code,
        message: missing.message,
        environment: environment,
      ))
    }

    var dataRootOverride: String?
    if let value = McpToolArguments.string(arguments, "data_root") {
      let dataRoot = WorkspacePath.absolute(value, relativeTo: workspaceRoot)
      guard WorkspacePath.isContained(root: workspaceRoot, child: dataRoot) else {
        return .refused(McpErrorEnvelope.make(
          command: command,
          code: "unsafe_data_root",
          message: "data_root must stay inside repo.",
          environment: environment,
        ))
      }
      dataRootOverride = dataRoot
    }

    let registry = try McpSchemaRegistry.load()
    do throws(WorkspaceError) {
      return try .resolved(WorkspaceContextResolver.resolve(
        options: ResolveWorkspaceContextOptions(
          workspaceRoot: workspaceRoot,
          dataRootOverride: dataRootOverride,
          component: McpToolArguments.string(arguments, "component"),
        ),
        registry: registry,
      ))
    } catch {
      throw McpToolFailure(error)
    }
  }
}
