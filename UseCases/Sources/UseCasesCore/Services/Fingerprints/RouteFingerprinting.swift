/// Computes a route's fingerprint (chapter 11 §49, §85, §89.4).
protocol RouteFingerprinting: Sendable {
  /// The canonical JSON payload that is hashed.
  func payload(of input: RouteFingerprintInput) throws(FingerprintingError) -> [UInt8]

  /// `uc-route-v1-sha256:` and the 64-character digest.
  func fingerprint(of input: RouteFingerprintInput) throws(FingerprintingError) -> String
}
