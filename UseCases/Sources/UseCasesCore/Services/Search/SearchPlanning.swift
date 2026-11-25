/// Reads what the command line asks of `search` into a plan (chapter 16 §15), before any
/// workspace is read.
public protocol SearchPlanning: Sendable {
  /// The plan a request asks for.
  ///
  /// - Throws: ``UseCaseSearchError`` for flags, words, a `--like` use case or a token that
  ///   cannot be read.
  func plan(_ request: SearchRequest) throws(UseCaseSearchError) -> SearchPlan
}
