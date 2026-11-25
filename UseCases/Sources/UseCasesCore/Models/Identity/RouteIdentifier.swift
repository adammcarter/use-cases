/// A validation route's id: a single segment, unique within its use case (chapters 02 and 05).
struct RouteIdentifier: Hashable, Sendable, CustomStringConvertible {
  let segment: IdentifierSegment

  /// Reads the id, refusing anything off the segment grammar.
  init(validating text: String) throws(IdentityError) {
    segment = try IdentifierSegment(validating: text)
  }

  var text: String {
    segment.text
  }

  var description: String {
    text
  }
}
