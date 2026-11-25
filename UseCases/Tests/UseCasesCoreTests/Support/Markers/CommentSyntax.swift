import Testing

/// The comment syntax a language wraps a sentinel in: what comes before and after it.
struct CommentSyntax: Sendable, CustomTestStringConvertible {
  let name: String
  let before: String
  let after: String

  var testDescription: String {
    name
  }
}
