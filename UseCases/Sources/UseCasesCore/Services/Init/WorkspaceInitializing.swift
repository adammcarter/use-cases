/// Plans `use-cases init` (chapter 17): what to write, what is kept and what to tell the person,
/// without writing anything. Every refusal of chapter 17 §3 and §9 comes from here, before the
/// first byte is written and before the first question is asked.
public protocol WorkspaceInitializing: Sendable {
  /// - Parameter request: The folder, the form and the prefix that were asked for.
  /// - Returns: The plan, ready for the shared writer to check on a copy and apply.
  /// - Throws: ``InitError``: the prefix is not one, the folder is not a folder, is inside a
  ///   workspace or is a child scope, the prefix differs from the existing workspace's, or the
  ///   root `use-cases.yml` cannot be used.
  func plan(_ request: InitRequest) throws(InitError) -> InitPlan
}
