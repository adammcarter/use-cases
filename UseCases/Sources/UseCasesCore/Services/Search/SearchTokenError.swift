/// Why a token cannot be read back.
enum SearchTokenError: Error, Equatable, Sendable {
  /// The text is not made of what ``SearchTokenCoding/token(for:)`` makes.
  case malformed
}
