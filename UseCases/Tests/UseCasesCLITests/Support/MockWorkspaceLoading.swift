import UseCasesCore

/// A loader that refuses every request, the way the test says, and shows what it was asked.
struct MockWorkspaceLoading: WorkspaceLoading {
  let refusal: @Sendable (WorkspaceStart) -> WorkspaceLoadingError

  /// Always refuses with this error.
  init(_ error: WorkspaceLoadingError) {
    refusal = { _ in error }
  }

  /// Refuses with a message that is the start it was given, so a test sees where it was told
  /// to look.
  static var echoingStart: MockWorkspaceLoading {
    MockWorkspaceLoading(
      refusal: { start in
        .noWorkspace(message: "\(start)")
      },
    )
  }

  init(refusal: @escaping @Sendable (WorkspaceStart) -> WorkspaceLoadingError) {
    self.refusal = refusal
  }

  func load(from start: WorkspaceStart) throws(WorkspaceLoadingError) -> LoadedWorkspace {
    throw refusal(start)
  }
}
