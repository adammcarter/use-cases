/// Turns a payload into the canonical JSON bytes a fingerprint hashes (chapter 11 §89.1).
protocol CanonicalJSONEncoding: Sendable {
  /// UTF-8, keys in unsigned byte order, no whitespace, no Unicode normalization.
  func encode(_ value: CanonicalValue) throws(CanonicalEncodingError) -> [UInt8]
}
