/// Checks a results response (chapter 10 §13, §14), ignoring every member it does not know
/// (chapter 10 §10).
protocol TransformerResultsReading: Sendable {
  /// - Parameters:
  ///   - response: A response that says contract 1.
  ///   - name: The transformer, for the message.
  ///   - links: The keys of the validation links of the request: all a result may name.
  /// - Returns: The results with a link's several results merged, the tests in no link, and the
  ///   words for people.
  /// - Throws: ``TransformerError``. Each result's link and status are checked before the shape
  ///   of the whole, so that the specific error wins; after them a missing member is malformed.
  func read(
    _ response: AuthoredObject,
    from name: String,
    links: Set<String>,
  ) throws(TransformerError) -> TransformerResults
}
