/// Plans `use-cases save` (chapter 16 §14): one use case created or replaced whole, and nothing
/// else in the workspace changed.
public protocol UseCaseSaving: Sendable {
  /// - Parameters:
  ///   - argument: What `--file` names: a YAML or JSON file, or `-` for the standard input.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  /// - Returns: The change, ready for the shared writer to check and write.
  /// - Throws: ``UseCaseEditingError`` when the input cannot be read, is not one use case that
  ///   passes the checks every use case file passes, has nowhere to go, or brings a sign-off.
  func plan(
    savingFrom argument: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseEditingError) -> UseCaseChange
}
