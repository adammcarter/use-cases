/// Draws the intent of a request: what and why, in a few lines (chapter 21 §7, step 2).
public protocol IntentRendering: Sendable {
  /// The intent the input holds. It comes before any use case, so no workspace is read.
  ///
  /// - Parameter argument: What `--file` names: a YAML or JSON file, or `-` for the standard
  ///   input.
  /// - Throws: ``LayoutRenderingError`` when the input cannot be read or has no `what` and `why`.
  func intent(readingFrom argument: String) throws(LayoutRenderingError) -> IntentLayout
}
