/// Decides where a new use case goes: the recommended structure decides, and nothing else can
/// (chapter 16 §14).
protocol UseCasePlacing: Sendable {
  /// - Parameters:
  ///   - identifier: The full id of a use case that is not in the workspace.
  ///   - workspace: The workspace it joins.
  /// - Throws: ``UseCaseEditingError`` when the id has no group, sits straight under a scope's
  ///   namespace, or is under no scope's namespace.
  func place(
    _ identifier: UseCaseIdentifier,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCasePlacement
}
