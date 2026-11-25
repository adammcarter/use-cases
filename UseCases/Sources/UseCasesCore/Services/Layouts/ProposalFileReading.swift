/// Reads the proposal file that `render` and `apply` are both sent (chapter 21 §7).
protocol ProposalFileReading: Sendable {
  /// The proposal the input holds.
  ///
  /// - Parameter argument: What `--file` names: a YAML or JSON file, or `-` for the standard
  ///   input.
  /// - Throws: ``LayoutRenderingError`` when the input cannot be read, is not a batch with the
  ///   keys of a proposal beside it, or holds a key of the wrong shape.
  func read(_ argument: String) throws(LayoutRenderingError) -> ProposalFile
}
