/// What validation decided for a route or a link (chapter 12 §13). Its raw value is the text the
/// store keeps.
enum Verdict: String, CaseIterable, Sendable {
  /// Validation completed and the expected behaviour was satisfied.
  case pass

  /// Validation completed and the expected behaviour was not satisfied.
  case fail

  /// Validation did not reach a verdict, for example a skipped test.
  case incomplete

  /// The validation mechanism failed for this route.
  case error
}
