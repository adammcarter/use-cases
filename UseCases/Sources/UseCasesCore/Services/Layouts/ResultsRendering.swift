/// Draws what was done and how each change was proven (chapter 21 §7, step 8).
public protocol ResultsRendering: Sendable {
  /// Where each use case the proposal saved stands, which ones it removed, and whether the gate
  /// passes. A gate that blocks is an answer, not a refusal.
  ///
  /// - Parameters:
  ///   - argument: What `--file` names: a YAML or JSON file, or `-` for the standard input.
  ///   - workspace: The workspace as it is, which loaded without a problem.
  ///   - links: What link resolution found in that workspace.
  /// - Throws: ``LayoutRenderingError`` when the input cannot be read, is not a proposal, has
  ///   not been applied, or the workspace cannot be judged.
  func results(
    readingFrom argument: String,
    in workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(LayoutRenderingError) -> ResultsLayout
}
