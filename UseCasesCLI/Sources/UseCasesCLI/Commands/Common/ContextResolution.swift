import UseCasesCore

/// A resolved workspace, or the refusal envelope and exit code to return.
enum ContextResolution {
  case resolved(ResolvedWorkspaceContext)
  case refused(CommandOutput)
}
