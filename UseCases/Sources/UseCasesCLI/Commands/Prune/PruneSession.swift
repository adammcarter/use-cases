import UseCasesCore

/// What `prune` works through besides the command line.
struct PruneSession {
  /// Reads the workspace and its links, as status does: prune keeps what status uses.
  let loader: any LinkedWorkspaceLoading

  /// Plans and removes the superseded runs.
  let pruner: any StorePruning

  /// Claims the removal from a cancellation, so a request stopped before it starts removes
  /// nothing.
  let cancellation: any CancellationScoping
}
