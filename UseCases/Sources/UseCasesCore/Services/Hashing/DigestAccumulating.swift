/// A SHA-256 digest built up from chunks (chapter 11), which gives what hashing all the bytes at
/// once would.
protocol DigestAccumulating: Sendable {
  /// Takes in the next bytes.
  mutating func add(_ chunk: [UInt8])

  /// The digest of everything taken in so far, as 64 lowercase hexadecimal characters.
  func hex() -> String
}
