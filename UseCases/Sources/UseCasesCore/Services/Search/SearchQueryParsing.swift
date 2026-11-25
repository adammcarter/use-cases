/// Reads the words typed after `search` (chapter 16 §15).
protocol SearchQueryParsing: Sendable {
  /// Words, `"phrases"` that must appear and `-words` or `-"phrases"` that leave a use case out.
  ///
  /// - Throws: ``UseCaseSearchError`` for a quote never closed, or for words with nothing to
  ///   look for.
  func query(
    from text: String,
    isExact: Bool,
  ) throws(UseCaseSearchError) -> SearchQuery
}
