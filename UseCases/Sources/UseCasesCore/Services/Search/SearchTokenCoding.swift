/// Turns the parameters of a search into the token `--next` takes, and back (chapter 16 §15).
/// `search` and `docs` page the same way.
protocol SearchTokenCoding: Sendable {
  /// The token: the parameters as compact JSON, in base64url without padding, so it holds only
  /// letters, digits, `-` and `_`, and begins with a letter. The same parameters always give the
  /// same token.
  func token(for parameters: StoreJSONValue) -> String

  /// The parameters a token holds.
  ///
  /// - Throws: ``SearchTokenError`` for text that is not a token.
  func parameters(in token: String) throws(SearchTokenError) -> AuthoredValue
}
