/// A binding's id: a single segment (chapter 05).
struct BindingIdentifier: Hashable, Sendable, CustomStringConvertible {
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
