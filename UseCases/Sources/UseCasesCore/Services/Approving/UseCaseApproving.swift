/// Plans `use-cases approve` (chapter 16 §14): the promise of each use case approved as it reads
/// now, on the use case itself.
public protocol UseCaseApproving: Sendable {
  /// - Parameters:
  ///   - identifiers: The full ids to sign off, or none under `all`.
  ///   - all: Every use case of the workspace, drafts included, in id order.
  ///   - approver: Who signs off, as typed after `--by`.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  /// - Returns: The change, ready for the shared writer to check and write.
  /// - Throws: ``UseCaseApprovingError`` when the name cannot be recorded, use cases are both
  ///   named and asked for with `--all` or neither, a use case is not in the workspace, or its
  ///   file cannot be edited by its lines.
  func plan(
    approving identifiers: [String],
    all: Bool,
    by approver: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseApprovingError) -> UseCaseApprovalChange
}
