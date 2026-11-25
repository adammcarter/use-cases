/// Reads the text of one authored file strictly (chapter 09 §14, ADR 017).
protocol YAMLReading: Sendable {
  /// Turns the text of a file into the value it holds, or refuses it.
  ///
  /// - Parameters:
  ///   - text: The file's text.
  ///   - file: The name every refusal message starts with.
  ///   - kind: Which kind of file it is.
  func read(
    _ text: String,
    file: String,
    kind: AuthoredFileKind,
  ) throws(YAMLReadingError) -> AuthoredValue
}
