/// Writes one text the way authored YAML spells it: plain when every reader would read it back as
/// the same text, and in double quotes otherwise (chapter 09 §14, reversed).
protocol YAMLScalarWriting: Sendable {
  /// The text as it is written after a key, after a `- `, or inside a list or mapping written
  /// on one line. Reading what is written, as text, gives `string` back, exactly.
  func text(
    of string: String,
    in context: YAMLScalarContext,
  ) -> String
}
