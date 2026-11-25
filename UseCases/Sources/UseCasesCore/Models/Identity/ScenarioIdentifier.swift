/// A scenario's id: a single segment, unique within its use case (chapter 02).
struct ScenarioIdentifier: Hashable, Sendable, CustomStringConvertible {
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
