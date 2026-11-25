/// Whether a use case that can be read is fully written (chapter 02 and 07 "Authored state").
///
/// INVALID is not a case: an INVALID use case has diagnostics and no model (chapter 09 §25).
enum AuthoredState: Equatable, Sendable {
  /// Readable but incomplete; `missing` says what is left, in the order a reader fills it in.
  case draft(missing: [ReadinessGap])

  /// Fully written.
  case ready
}
