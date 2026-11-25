/// Finds where a test is declared by looking for its declaration text in source files.
protocol SourceSearching: Sendable {
  /// The one line, in `files`, that holds any of `needles`. Several such lines anywhere are
  /// ambiguous, and none is missing: a declaration is never guessed.
  mutating func find(
    needles: [String],
    in files: [String],
  ) -> DeclarationSearch

  /// The lines of a workspace file, nil when it cannot be read as UTF-8 text.
  mutating func lines(of file: String) -> [String]?
}
