/// Turns bytes into the SHA-256 digest every fingerprint is built from (chapter 11).
protocol Hashing: Sendable {
  func sha256Hex(of bytes: [UInt8]) -> String

  /// A digest that takes its bytes a chunk at a time, for what is too big to hold.
  func accumulator() -> any DigestAccumulating
}
