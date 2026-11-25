/// The links one source gave, and what it had to say about them.
struct LinkFindings: Equatable, Sendable {
  var links: [ResolvedLink]
  var diagnostics: [Diagnostic]

  /// Nothing found yet.
  static let empty = LinkFindings(
    links: [],
    diagnostics: [],
  )
}
