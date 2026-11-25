/// The lines of a file a manual binding points at (chapter 08 "Manual bindings"): 1-based and
/// inclusive. Whether it fits the file is checked against the file, later.
struct ManualRange: Equatable, Sendable {
  let start: SourcePosition
  let end: SourcePosition

  /// Whether the start comes after the end. On one line, a missing column is the start or the
  /// end of the line itself, so only two columns can disagree, and an end column one less than
  /// the start column is the empty range chapter 08 allows, not a start after the end.
  var startsAfterEnd: Bool {
    if start.line != end.line {
      return start.line > end.line
    }

    guard let startColumn = start.column, let endColumn = end.column else {
      return false
    }

    return startColumn > endColumn + 1
  }
}
