/// Reads a links response (chapter 10 §11), ignoring every member it does not know (chapter 10
/// §10).
protocol LinksResponseReading: Sendable {
  /// - Parameters:
  ///   - response: A response that says contract 1.
  ///   - name: The transformer, for the message.
  /// - Throws: ``TransformerError/malformedResponse(name:reason:)`` when `links` is not a list of
  ///   objects, or a member the core knows has the wrong type.
  func read(
    _ response: AuthoredObject,
    from name: String,
  ) throws(TransformerError) -> LinksAnswer
}
