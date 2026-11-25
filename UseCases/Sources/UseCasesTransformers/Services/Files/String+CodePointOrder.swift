extension String {
  /// Whether this text sorts before `other` by Unicode code point, the same order on every system.
  func precedesByCodePoint(_ other: String) -> Bool {
    utf8.lexicographicallyPrecedes(other.utf8)
  }
}
