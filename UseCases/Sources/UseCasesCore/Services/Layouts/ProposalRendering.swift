/// Draws the proposal the person signs off (chapter 21 §7, step 5).
public protocol ProposalRendering: Sendable {
  /// The whole change: each use case it names, the choices, and who signs.
  ///
  /// - Parameters:
  ///   - argument: What `--file` names: a YAML or JSON file, or `-` for the standard input.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  /// - Throws: ``LayoutRenderingError`` when the input cannot be read, is not a proposal, or
  ///   names a use case or a scenario that is not there.
  func proposal(
    readingFrom argument: String,
    in workspace: LoadedWorkspace,
  ) throws(LayoutRenderingError) -> ProposalLayout
}
