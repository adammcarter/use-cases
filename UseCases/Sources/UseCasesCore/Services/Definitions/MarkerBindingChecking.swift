/// Refuses a marker written as a YAML binding: markers are found in the code (chapter 08).
protocol MarkerBindingChecking: Sendable {
  /// A problem for each binding of a use case or a route that says `kind: marker`. It reads the
  /// file's value as written, before and independent of the schema, and skips what is not the
  /// shape of a definition file: the schema reports that.
  func check(
    _ value: AuthoredValue,
    file: WorkspacePath,
  ) -> MarkerBindingFindings
}
