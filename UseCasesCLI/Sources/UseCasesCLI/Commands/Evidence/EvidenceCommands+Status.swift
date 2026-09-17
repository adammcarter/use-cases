import UseCasesCore

/// `evidence status`: replay the history; `ok` and the exit code follow its
/// completeness.
extension EvidenceCommands {
  static func runStatus(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "evidence.status"
    let workspace: ResolvedWorkspaceContext
    switch try WorkspaceContextLoader.resolve(arguments: context.arguments, command: command) {
    case let .refused(output):
      return output
    case let .resolved(resolved):
      workspace = resolved
    }

    let snapshot: EvidenceSnapshot
    do throws(EvidenceEventError) {
      snapshot = try EvidenceReplay.replay(context: workspace)
    } catch {
      throw CommandFailure(error)
    }
    let result = CliResult.make(
      command: command,
      data: snapshot.statusResult(),
      isSuccessful: snapshot.isComplete,
      isComplete: snapshot.isComplete,
      diagnostics: snapshot.diagnostics,
      workspaceRoot: workspace.workspaceRoot,
      dataRoot: workspace.dataRoot,
      componentIdentifier: workspace.componentIdentifier,
    )
    return CommandOutput(result: result, exitCode: snapshot.isComplete ? 0 : 1)
  }
}
