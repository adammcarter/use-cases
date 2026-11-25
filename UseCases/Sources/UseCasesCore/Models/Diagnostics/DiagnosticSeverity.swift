/// Whether a diagnostic makes the workspace INVALID or is only a warning (chapter 09 §26).
enum DiagnosticSeverity: Int, Comparable, Sendable {
  case error
  case warning

  static func < (
    lhs: DiagnosticSeverity,
    rhs: DiagnosticSeverity,
  ) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}
