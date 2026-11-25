/// Reads what the command line asks of a search of the guides into a plan (chapter 16 §16).
public protocol GuidePlanning: Sendable {
  /// The plan for words typed after `docs`.
  ///
  /// - Throws: ``GuideSearchError`` for words that cannot be searched for, or a page size that
  ///   is not 1 to 100.
  func plan(
    words: String,
    isExact: Bool,
    pageSize: String?,
  ) throws(GuideSearchError) -> GuidePlan

  /// The plan the following page of an earlier search continues.
  ///
  /// - Throws: ``GuideSearchError`` for text that is not a token `docs` made.
  func plan(continuing token: String) throws(GuideSearchError) -> GuidePlan
}
