/// Normalized content reduced to a digest and a length (chapter 11 §89.3), so a large file never
/// enters a payload.
struct ContentReference: Equatable, Sendable {
  /// The only algorithm V1 has.
  static let algorithm = "sha256"

  /// The length of the normalized bytes that were hashed, not of the framing.
  let byteLength: Int

  /// 64 lowercase hexadecimal characters: the domain-framed hash of the normalized bytes.
  let digest: String

  /// How the content reference is shown outside a payload: `uc-content-v1-sha256:<digest>`.
  var fingerprint: String {
    (FingerprintDomain.content.externalPrefix ?? "") + digest
  }

  /// The three members of a content reference.
  var canonical: CanonicalValue {
    .members([
      "algorithm": .string(Self.algorithm),
      "byte_length": .integer(byteLength),
      "digest": .string(digest),
    ])
  }

  /// Sorts by digest, then by length, then by algorithm (§89.5): one algorithm exists, so the
  /// last step never decides.
  func precedes(_ other: ContentReference) -> Bool {
    if !digest.isExactlyEqual(to: other.digest) {
      return digest.precedesExactly(other.digest)
    }

    return byteLength < other.byteLength
  }
}
