/// Answers `docs` (chapter 16 §16): the list of guides, one guide, or a page of sections.
public protocol DocsAnswering: Sendable {
  /// The answer to a request.
  ///
  /// - Throws: ``DocsError`` for guides that cannot be read, or a request that is refused.
  func answer(_ request: DocsRequest) throws(DocsError) -> DocsAnswer
}
