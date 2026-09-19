import UseCasesCore

/// `matrix validate`, `matrix list` and `matrix status`: read-only, each
/// loading the matrix afresh.
extension MatrixCommands {
  /// Always `ok`, even when the matrix is incomplete; the exit code carries it.
  static func runValidate(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "matrix.validate"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let snapshot = try loadMatrix(workspace)
    let result = CliResult.make(
      command: command,
      data: snapshot.validationResult(),
      isSuccessful: true,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: snapshot.isComplete ? 0 : 1)
  }

  /// `ok` unless `--strict` meets an incomplete matrix, which exits 3.
  static func runList(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "matrix.list"
    let isStrict = context.flags["strict"] == .boolean(true)
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let snapshot = try loadMatrix(workspace)
    let selected = snapshot.queryUseCases(UseCaseQuery(
      valueTiers: strings(context.flags["value"]),
      journeyRoles: strings(context.flags["journeyRole"]),
      lifecycles: strings(context.flags["lifecycle"]),
      hostSurfaces: strings(context.flags["host"]),
      tagsAny: strings(context.flags["tag"]),
      changedPaths: strings(context.flags["changedPath"]),
    ))
    let isSuccessful = isStrict ? snapshot.isComplete : true
    let result = CliResult.make(
      command: command,
      data: snapshot.listResult(for: selected),
      isSuccessful: isSuccessful,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: isSuccessful ? 0 : 3)
  }

  /// The matrix and the evidence history together; complete only when both are.
  static func runStatus(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "matrix.status"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let matrix = try loadMatrix(workspace)
    let evidence: EvidenceSnapshot
    do throws(EvidenceEventError) {
      evidence = try EvidenceReplay.replay(context: workspace)
    } catch {
      throw CommandFailure(error)
    }
    let isComplete = matrix.isComplete && evidence.isComplete
    let data = JSONValue.object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("matrix", matrix.validationResult()),
      ("evidence", evidence.statusResult()),
    ]))
    let result = CliResult.make(
      command: command,
      data: data,
      isSuccessful: isComplete,
      isComplete: isComplete,
      diagnostics: matrix.diagnostics + evidence.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: isComplete ? 0 : 1)
  }

  static func loadMatrix(_ workspace: ResolvedWorkspaceContext) throws(CommandFailure)
    -> MatrixSnapshot
  {
    let registry = try SchemaRegistryLoader.load()
    do throws(UseCaseMatrixError) {
      return try UseCaseMatrixLoader.load(context: workspace, registry: registry)
    } catch {
      throw CommandFailure(error)
    }
  }

  /// A repeatable flag's values; an absent flag places no constraint.
  private static func strings(_ value: ParsedFlagValue?) -> [String] {
    guard case let .strings(values) = value else {
      return []
    }
    return values
  }
}
