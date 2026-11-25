/// Shows one use case of a loaded workspace, whole (chapter 16 §14).
public protocol UseCaseShowing: Sendable {
  /// The use case with exactly this full id. A prefix, or an id without its group, names
  /// nothing here.
  ///
  /// - Throws: ``UseCaseShowingError`` when the workspace has no such use case.
  func show(
    _ identifier: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseShowingError) -> ShownUseCase
}
