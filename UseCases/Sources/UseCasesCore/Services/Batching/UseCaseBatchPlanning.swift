/// Plans a batch (chapter 16 §14, ADR 031): every change made to the files as the changes before
/// it left them, in one fixed order, and nothing written.
protocol UseCaseBatchPlanning: Sendable {
  /// - Parameters:
  ///   - batch: What to remove and what to save.
  ///   - approver: Who signed the batch off, when it was: each use case it saves is approved as
  ///     it now reads.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  ///   - links: Its links, from which the markers that still name a removed use case are listed.
  /// - Returns: The change, ready for the shared writer to check and write.
  /// - Throws: ``UseCaseBatchError`` when a use case is in the batch twice, a removal is of a
  ///   use case that is not there, a save is refused as `save` refuses it, or a file cannot be
  ///   edited by its lines.
  func plan(
    _ batch: UseCaseBatch,
    approvedBy approver: ApproverName?,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseBatchError) -> UseCaseBatchChange
}
