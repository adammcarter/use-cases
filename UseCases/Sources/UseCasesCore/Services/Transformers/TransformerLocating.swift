import Foundation

/// Finds the program a transformer reference names (chapter 10 §9).
protocol TransformerLocating: Sendable {
  /// The start of the command that runs the transformer: the program, and for a bundled
  /// transformer its name, which the one program of the bundled transformers takes first. The
  /// job and the two files follow.
  ///
  /// - Parameters:
  ///   - reference: What the bridge settings name.
  ///   - root: The workspace root, which a project-relative program path is relative to.
  /// - Throws: ``TransformerError/programMissing(name:expectedAt:)`` when the bundled transformers
  ///   program is not beside the running executable.
  func command(
    for reference: TransformerReference,
    in root: URL,
  ) throws(TransformerError) -> [String]
}
