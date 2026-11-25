/// Refuses what belongs in the bridge settings when it is written in a use case or a route
/// (chapter 02 "Not stored here", chapter 06 "Where running lives").
protocol TechnicalFieldChecking: Sendable {
  /// A diagnostic for each technical field a use case or a route writes. It reads the file's
  /// value as written, before and independent of the schema, and skips what is not the shape
  /// of a definition file: the schema reports that.
  func check(
    _ value: AuthoredValue,
    file: WorkspacePath,
  ) -> [Diagnostic]
}
