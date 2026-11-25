/// Reads a definition file's value that is already in memory, as the loader reads one from disk.
protocol DefinitionValueReading: Sendable {
  /// The file's use cases, or every problem in the value, found by the checks every definition
  /// file passes.
  ///
  /// - Parameters:
  ///   - value: What the file holds.
  ///   - path: The file, as diagnostics name it.
  func definitionFile(
    from value: AuthoredValue,
    at path: WorkspacePath,
  ) throws(DefinitionFileLoadingError) -> DefinitionFile
}
