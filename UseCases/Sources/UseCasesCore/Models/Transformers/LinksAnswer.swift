/// What a links transformer said once its response is known to be shaped as chapter 10 §11 says.
struct LinksAnswer: Equatable, Sendable {
  let links: [TransformerLink]

  /// Words for people. `nil` when the response has no `diagnostics`, which is an error that
  /// comes after the links are checked, so that the more specific error about a link wins.
  let diagnostics: [String]?
}
