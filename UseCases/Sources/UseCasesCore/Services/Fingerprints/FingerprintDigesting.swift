/// Frames a payload with its domain and hashes it (chapter 11 §89.2).
protocol FingerprintDigesting: Sendable {
  /// The 64 lowercase hexadecimal characters of the SHA-256 of
  /// `domain || 0x00 || decimal length || ":" || payload`.
  func digest(
    of payload: [UInt8],
    in domain: FingerprintDomain,
  ) -> String

  /// The same digest for a payload of a length that is known before it is read, which is given a
  /// chunk at a time: the digest is the one ``digest(of:in:)`` gives for the payload at once.
  ///
  /// - Parameters:
  ///   - domain: The domain the payload is framed with.
  ///   - length: How many bytes the payload will have. Fewer or more is a wrong digest.
  func accumulator(
    in domain: FingerprintDomain,
    payloadLength length: Int,
  ) -> any DigestAccumulating
}
