/// One or more segments joined with `.` (chapter 05): a prefix, or a whole use-case id.
struct Namespace: Hashable, Sendable, CustomStringConvertible {
  /// The segments in order. Never empty.
  let segments: [IdentifierSegment]

  /// Reads a namespace, refusing an empty piece and anything off the segment grammar.
  init(validating text: String) throws(IdentityError) {
    guard !text.isEmpty else {
      throw .empty
    }

    var parsed: [IdentifierSegment] = []

    for piece in text.splitOnScalar(".") {
      if piece.isEmpty {
        throw .emptySegment(within: text)
      }

      do {
        try parsed.append(IdentifierSegment(validating: piece))
      } catch {
        throw error.naming(wholeText: text)
      }
    }

    segments = parsed
  }

  /// A namespace of one segment.
  init(_ segment: IdentifierSegment) {
    segments = [segment]
  }

  private init(segments: [IdentifierSegment]) {
    self.segments = segments
  }

  var text: String {
    segments.map(\.text).joined(separator: ".")
  }

  var description: String {
    text
  }

  /// This namespace followed by another.
  func appending(_ other: Namespace) -> Namespace {
    Namespace(segments: segments + other.segments)
  }
}
