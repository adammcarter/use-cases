/// Computes the fingerprint of a use case's promise (chapter 11 §89.9), which a sign-off pins.
protocol PromiseFingerprinting: Sendable {
  /// The canonical JSON payload that is hashed.
  func payload(of input: PromiseFingerprintInput) throws(FingerprintingError) -> [UInt8]

  /// The 64 lowercase hexadecimal characters of the digest, with no prefix.
  func fingerprint(of input: PromiseFingerprintInput) throws(FingerprintingError) -> String
}
