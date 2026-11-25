/// Plans `use-cases apply` (chapter 16 §14, ADR 031): a batch of removals and saves, all of it or
/// none of it.
public protocol UseCaseApplying: Sendable {
  /// - Parameters:
  ///   - argument: What `--file` names: a YAML or JSON file, or `-` for the standard input.
  ///   - approver: What `--approved-by` was given, or `nil`: the batch was signed off, so each
  ///     use case it saves is approved as it now reads, under this name.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  ///   - links: Its links, from which the markers that still name a removed use case are listed.
  /// - Returns: The change, ready for the shared writer to check and write.
  /// - Throws: ``UseCaseBatchError`` when the name cannot be recorded, the input cannot be read
  ///   or is not a batch, a use case is in it twice, or a change is refused as `save` and
  ///   `remove` refuse theirs.
  func plan(
    applyingFrom argument: String,
    approvedBy approver: String?,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseBatchError) -> UseCaseBatchChange
}
