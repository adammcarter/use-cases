/// Why an authored value is not the shape a model reads. A value that passed its schema never
/// raises one of these; they are the answer for a value that was never checked, so a model
/// refuses it instead of guessing.
///
/// `location` is where in the value it happened, such as `scenarios[1].id`; empty for the
/// value itself.
enum AuthoredShapeError: Error, Equatable, Sendable {
  /// A mapping was expected.
  case notAnObject(location: String)

  /// A required member is not there.
  case missing(location: String)

  /// The value has another type than the one the field takes, such as `a list`.
  case wrongType(location: String, expected: String)

  /// Text that is none of the values a field allows.
  case unknownChoice(location: String, text: String)

  /// Text off the id grammar.
  case invalidIdentifier(location: String, IdentityError)

  /// Text that is not a workspace path.
  case invalidPath(location: String, WorkspacePathError)

  /// Text that is not a path pattern.
  case invalidPattern(location: String, PathPatternError)

  /// A line or column below 1.
  case invalidPosition(location: String, SourcePositionError)

  /// Text that is not a calendar day written `YYYY-MM-DD`.
  case invalidDate(location: String, text: String)

  /// A value the field's own rules refuse, such as a run id; `reason` says why.
  case invalidValue(location: String, reason: String)
}
