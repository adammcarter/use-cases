/// Decides whether text matches a query, and how well (chapter 16 §15). `search` and `docs` match
/// the same way.
protocol TextMatching: Sendable {
  /// How the passages match the query; `nil` when they do not: a phrase is missing, a word to
  /// leave out is there, or none of the words is.
  func match(
    _ query: SearchQuery,
    in passages: [SearchPassage],
  ) -> TextMatch?
}
