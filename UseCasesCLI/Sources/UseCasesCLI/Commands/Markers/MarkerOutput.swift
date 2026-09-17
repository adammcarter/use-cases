import UseCasesCore

/// `markerOutput`: a marker command's result as its envelope's data, `ok` and
/// `complete` both the given verdict, the workspace trio in the context, and
/// the result's own exit code.
enum MarkerOutput {
  static func make(
    command: String,
    result: JSONValue,
    exitCode: Int,
    isOK: Bool,
    workspace: ResolvedWorkspaceContext,
  ) -> CommandOutput {
    CommandOutput(
      result: CliResult.make(
        command: command,
        data: result,
        isSuccessful: isOK,
        isComplete: isOK,
        workspaceRoot: workspace.workspaceRoot,
        dataRoot: workspace.dataRoot,
        componentIdentifier: workspace.componentIdentifier,
      ),
      exitCode: Int32(exitCode),
    )
  }
}
