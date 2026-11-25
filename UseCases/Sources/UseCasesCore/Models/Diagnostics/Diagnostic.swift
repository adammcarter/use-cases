/// One problem found in the workspace, with the file it is in and, when known, the place.
///
/// Diagnostics sort by file, then position, then code (chapter 09 §27.1), so a report reads the
/// same however the work was scheduled. A diagnostic with no position sorts before one with a
/// position in the same file. Severity never changes that order; it only separates two
/// diagnostics that agree on everything else.
struct Diagnostic: Hashable, Comparable, Sendable, CustomStringConvertible {
  let file: WorkspacePath
  let position: SourcePosition?
  let code: DiagnosticCode
  let severity: DiagnosticSeverity
  let message: String

  /// Makes a diagnostic.
  init(
    file: WorkspacePath,
    position: SourcePosition?,
    code: DiagnosticCode,
    severity: DiagnosticSeverity,
    message: String,
  ) {
    self.file = file
    self.position = position
    self.code = code
    self.severity = severity
    self.message = message
  }

  /// `<file>:<line>: <message>`, or `<file>: <message>` when there is no line.
  var description: String {
    guard let position else {
      return "\(file.text): \(message)"
    }

    return "\(file.text):\(position.line): \(message)"
  }

  static func == (
    lhs: Diagnostic,
    rhs: Diagnostic,
  ) -> Bool {
    lhs.file == rhs.file
      && lhs.position == rhs.position
      && lhs.code == rhs.code
      && lhs.severity == rhs.severity
      && lhs.message.isExactlyEqual(to: rhs.message)
  }

  static func < (
    lhs: Diagnostic,
    rhs: Diagnostic,
  ) -> Bool {
    if lhs.file != rhs.file {
      return lhs.file < rhs.file
    }

    if lhs.position != rhs.position {
      return lhs.position.precedesNilFirst(rhs.position)
    }

    if lhs.code != rhs.code {
      return lhs.code < rhs.code
    }

    if !lhs.message.isExactlyEqual(to: rhs.message) {
      return lhs.message.precedesExactly(rhs.message)
    }

    return lhs.severity < rhs.severity
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(file)
    hasher.combine(position)
    hasher.combine(code)
    hasher.combine(severity)
    message.hashExactly(into: &hasher)
  }
}
