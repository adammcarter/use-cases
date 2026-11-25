/// Reads a scope's `use-cases.yml` once it has passed the workspace schema (chapter 04 and 09 §8).
protocol ScopeConfigurationReading: Sendable {
  /// The configuration with its defaults filled in, or every problem in the file.
  ///
  /// - Parameters:
  ///   - value: The file's value, already checked against the workspace schema.
  ///   - file: The file, as diagnostics name it.
  ///   - role: Whether the file is the workspace root's or a child scope's.
  func read(
    _ value: AuthoredValue,
    file: WorkspacePath,
    role: ScopeRole,
  ) throws(ScopeConfigurationReadingError) -> ScopeConfiguration
}
