/// Whether PEM text is key material the signed tier can use — the up-front
/// check the CLI makes where the TypeScript calls node's `createPublicKey` and
/// `createPrivateKey`.
///
/// Stricter than node: node also accepts RSA, EC and other key types here and
/// fails later, at signing or verification; these accept ed25519 only.
public enum Ed25519KeyMaterial {
  /// node's OpenSSL detail for text it cannot decode as any key.
  public static let decoderFailureDetail = "error:1E08010C:DECODER routines::unsupported"

  /// An SPKI `PUBLIC KEY`, or a PKCS#8 `PRIVATE KEY` whose public half is used.
  public static func isPublicKey(pem: String) -> Bool {
    Ed25519PEM.publicKey(fromPEM: pem) != nil
  }

  /// A PKCS#8 `PRIVATE KEY`.
  public static func isPrivateKey(pem: String) -> Bool {
    Ed25519PEM.privateKey(fromPEM: pem) != nil
  }

  /// `samePublicKey`: the same text, or the same key once decoded — the
  /// comparison the TypeScript makes by re-exporting both through
  /// `createPublicKey`. Two PEMs that are not ed25519 keys are never the same
  /// key here, where node would compare whatever it could decode.
  public static func isSamePublicKey(
    _ left: String,
    _ right: String,
  ) -> Bool {
    if JavaScriptString.identical(left, right) {
      return true
    }
    guard let decodedLeft = Ed25519PEM.publicKey(fromPEM: left),
          let decodedRight = Ed25519PEM.publicKey(fromPEM: right)
    else {
      return false
    }
    return decodedLeft.rawRepresentation == decodedRight.rawRepresentation
  }
}
