extension String {
  /// Equal only when the UTF-8 bytes are equal. `==` also treats `é` written as one scalar and
  /// as two as the same text, which chapter 04's "on-disk spelling, Unicode form included" forbids.
  func isExactlyEqual(to other: String) -> Bool {
    utf8.elementsEqual(other.utf8)
  }

  /// Orders by UTF-8 bytes: the same on every machine and locale.
  func precedesExactly(_ other: String) -> Bool {
    utf8.lexicographicallyPrecedes(other.utf8)
  }

  /// Hashes the UTF-8 bytes, to agree with `isExactlyEqual(to:)`.
  func hashExactly(into hasher: inout Hasher) {
    for byte in utf8 {
      hasher.combine(byte)
    }
  }
}
