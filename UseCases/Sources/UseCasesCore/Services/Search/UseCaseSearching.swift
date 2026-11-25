/// Finds the use cases of a loaded workspace that match a search (chapter 16 §15).
public protocol UseCaseSearching: Sendable {
  /// One page of the use cases that match, best first, ties by id.
  ///
  /// - Parameters:
  ///   - plan: What to look for and which page.
  ///   - workspace: A workspace that loaded.
  ///   - status: What `status` says of it, which is what `--state` and each match's state are
  ///     read from.
  /// - Throws: ``UseCaseSearchError`` for a filter that names nothing, and, for a page after the
  ///   first, when the use cases, their statuses or the group's members are not as they were.
  func search(
    _ plan: SearchPlan,
    in workspace: LoadedWorkspace,
    status: WorkspaceStatus,
  ) throws(UseCaseSearchError) -> SearchPage
}
