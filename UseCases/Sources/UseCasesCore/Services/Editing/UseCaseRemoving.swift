/// Plans `use-cases remove` (chapter 16 §14): one use case taken out, its evidence left where it
/// is, and the markers that still name it listed.
public protocol UseCaseRemoving: Sendable {
  /// - Parameters:
  ///   - identifier: The full id of the use case.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  ///   - links: Its links, from which the markers that still name the use case are listed.
  /// - Returns: The change, ready for the shared writer to check and write.
  /// - Throws: ``UseCaseEditingError`` when the workspace has no such use case, or its file cannot
  ///   be edited by its lines.
  func plan(
    removing identifier: String,
    in workspace: LoadedWorkspace,
    links: [ResolvedLink],
  ) throws(UseCaseEditingError) -> UseCaseChange
}
