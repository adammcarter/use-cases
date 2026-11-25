/// Why a piece of text is not a path pattern (chapter 04, "Path patterns").
enum PathPatternError: Error, Equatable, Sendable {
  /// The text breaks a rule of workspace paths: empty, absolute, `..`, a backslash, a `.` or
  /// empty segment, and so on.
  case invalidPath(WorkspacePathError)

  /// `**` is part of a longer segment: `a**`, `**a`, `***`.
  case doubleStarNotWholeSegment(String, within: String)
}

extension PathPatternError: CustomStringConvertible {
  var description: String {
    switch self {
    case let .invalidPath(error):
      "'\(error.offendingText)' is not a valid pattern: \(error.reason)"
    case let .doubleStarNotWholeSegment(segment, text):
      "'\(text)' is not a valid pattern: '**' must be a whole segment, not part of '\(segment)'"
    }
  }
}
