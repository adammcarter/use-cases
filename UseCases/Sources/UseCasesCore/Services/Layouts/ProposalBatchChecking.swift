/// Holds a proposal's batch to what `apply` holds a batch to.
protocol ProposalBatchChecking: Sendable {
  /// Plans the batch against the workspace as `apply --dry-run` does, and writes nothing.
  ///
  /// - Parameters:
  ///   - proposal: The proposal file.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  /// - Throws: ``LayoutRenderingError/batch(_:)`` with the very refusal `apply` gives.
  func check(
    _ proposal: ProposalFile,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError)
}
