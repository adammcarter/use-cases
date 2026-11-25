/// Finds a comment that would silently cut the text before it (chapter 09 §14).
protocol TrailingCommentScanning: Sendable {
  /// Looks at what follows a plain scalar whose text begins at `index` in the source.
  func finding(
    afterPlainScalar value: String,
    startingAt index: Int,
    in source: YAMLSourceText,
  ) -> TrailingCommentFinding
}

/// What follows a plain scalar on its line.
enum TrailingCommentFinding: Equatable, Sendable {
  /// Nothing, or something that cuts no text.
  case noComment

  /// A comment that YAML reads as the end of the text.
  case cutsText(YAMLComment)

  /// The scalar could not be found in the source, so nothing can be said about it.
  case lost
}
