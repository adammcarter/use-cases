/// Draws the cards of a proposal (chapter 21 §7, step 4).
public protocol BriefRendering: Sendable {
  /// A card for each use case the proposal adds, changes or removes; the untouched have none.
  ///
  /// - Parameters:
  ///   - argument: What `--file` names: a YAML or JSON file, or `-` for the standard input.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  /// - Throws: ``LayoutRenderingError`` when the input cannot be read, is not a proposal, or
  ///   names a use case or a scenario that is not there.
  func brief(
    readingFrom argument: String,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> BriefLayout
}
