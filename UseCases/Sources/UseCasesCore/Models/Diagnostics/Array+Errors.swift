extension [Diagnostic] {
  /// Whether any of them makes the workspace INVALID.
  var containsError: Bool {
    contains { diagnostic in
      diagnostic.severity == .error
    }
  }
}
