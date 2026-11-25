/// One way a value breaks a schema: where it sits in the document, which keyword it broke, and
/// what is wrong with it.
struct SchemaFailure: Hashable, Comparable, Sendable {
  /// Steps from the top of the document to the offending value; empty for the document itself.
  let path: [SchemaPathStep]

  /// The keyword that failed, so a caller can word the failure its own way.
  let keyword: SchemaKeyword

  /// What is wrong, for example `42 is not of type 'string'`.
  let message: String

  /// The names of the members a `required` or an `additionalProperties` failure is about, so a
  /// caller can word it its own way; empty for every other failure.
  var members: [String] = []

  /// The path as text, steps joined by `/`: `groups/g/include/globs/0`. Empty for the document.
  var pathText: String {
    path.map(\.text).joined(separator: "/")
  }

  /// The failure as one line: the message, then where it is.
  var description: String {
    path.isEmpty ? message : "\(message) at \(pathText)"
  }

  static func == (
    lhs: SchemaFailure,
    rhs: SchemaFailure,
  ) -> Bool {
    lhs.path == rhs.path
      && lhs.keyword == rhs.keyword
      && lhs.message.hasSameScalars(as: rhs.message)
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(path)
    hasher.combine(keyword)
    hasher.combine(ExactText(message))
  }

  /// Failures order by path, then by keyword in the order of ``SchemaKeyword``, then by message,
  /// so a list of them reads the same every time.
  static func < (
    lhs: SchemaFailure,
    rhs: SchemaFailure,
  ) -> Bool {
    if lhs.path != rhs.path {
      return lhs.path.lexicographicallyPrecedes(rhs.path)
    }
    if lhs.keyword != rhs.keyword {
      return lhs.keyword < rhs.keyword
    }

    return lhs.message.precedesByScalars(rhs.message)
  }
}
