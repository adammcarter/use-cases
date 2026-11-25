/// Sets each use case of a proposal against the workspace (chapter 21 §5).
protocol ProposalChangeResolving: Sendable {
  /// Every use case the proposal names, in the order new, extends, changes, replaces,
  /// untouched, and within a fit in the order the file lists them.
  ///
  /// - Parameters:
  ///   - proposal: The proposal file.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  /// - Throws: ``LayoutRenderingError`` when the proposal removes or leaves untouched a use case
  ///   the workspace does not have, names one both as untouched and in the batch, or points
  ///   `fits`, `you_see` or `golden` at something it does not hold.
  func changes(
    of proposal: ProposalFile,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> [ResolvedChange]

  /// The checks of a proposal that has been applied: the use cases it leaves untouched are
  /// there, and everything `fits`, `you_see` and `golden` point at is in the proposal.
  ///
  /// - Throws: ``LayoutRenderingError`` as ``changes(of:in:)`` does, for what it checks.
  func checkReferences(
    of proposal: ProposalFile,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError)
}
