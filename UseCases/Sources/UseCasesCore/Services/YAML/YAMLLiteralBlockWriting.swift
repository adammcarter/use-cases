/// Writes multi-line text as a literal block when every YAML reader reads it back exactly.
protocol YAMLLiteralBlockWriting: Sendable {
  /// The text as a literal block under a key or a dash that sits `parentIndent` spaces in, or
  /// `nil` when a block cannot hold the text exactly: it has no line break, no character that is
  /// not a space or a line break, or a character other than a line break and a tab that YAML
  /// would escape (a control character, a carriage return, `U+0085`, `U+2028`, `U+2029`).
  func block(
    of text: String,
    parentIndent: Int,
  ) -> YAMLLiteralBlock?
}
