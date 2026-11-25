/// One way a JSON document breaks a schema, in the shape a caller outside the core words its own
/// refusals from. A `path` is the steps from the top of the document, joined by `/`; empty for
/// the document itself.
public enum JSONSchemaProblem: Equatable, Sendable {
  /// The text is not JSON.
  case unreadable(reason: String)

  /// A member the schema requires is not there.
  case missing(
    path: String,
    member: String,
  )

  /// Members the schema does not list, where it allows none.
  case unexpected(
    path: String,
    members: [String],
  )

  /// Any other keyword broken, such as `type` or `enum`; `message` says what is wrong.
  case breaks(
    path: String,
    keyword: String,
    message: String,
  )
}
