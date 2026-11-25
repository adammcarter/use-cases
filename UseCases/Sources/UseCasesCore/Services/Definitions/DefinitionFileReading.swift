/// Reads a use-case definition file once it has passed the use-cases schema (chapter 02 and
/// chapter 09 §13 steps 5 to 8).
protocol DefinitionFileReading: Sendable {
  /// The file's use cases in the order written, or every problem in the file: one broken use
  /// case does not hide the problems of the others.
  ///
  /// - Parameters:
  ///   - value: The file's value, already checked against the use-cases schema.
  ///   - file: The file, as diagnostics name it.
  func read(
    _ value: AuthoredValue,
    file: WorkspacePath,
  ) throws(DefinitionFileReadingError) -> DefinitionFile
}
