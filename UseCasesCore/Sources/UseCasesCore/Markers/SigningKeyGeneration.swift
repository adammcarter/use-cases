import Crypto

/// A freshly minted ed25519 keypair in the PEM forms the tool consumes.
public struct SigningKeypair: Equatable, Sendable {
  /// PKCS#8 PEM. The PRIVATE key: it belongs only in CI secrets.
  public let privatePEM: String
  /// SPKI PEM. The PUBLIC key: safe to commit.
  public let publicPEM: String
}

/// `use-cases keygen`'s keypair generation (keygen.ts): pure crypto over in-memory
/// values, with no filesystem access.
public enum SigningKeyGeneration {
  /// A new, distinct keypair on every call.
  public static func generate() -> SigningKeypair {
    let privateKey = Curve25519.Signing.PrivateKey()
    return SigningKeypair(
      privatePEM: Ed25519PEM.pem(
        label: "PRIVATE KEY",
        der: Ed25519PEM.privateKeyPrefix + [UInt8](privateKey.rawRepresentation),
      ),
      publicPEM: Ed25519PEM.pem(
        label: "PUBLIC KEY",
        der: Ed25519PEM.publicKeyPrefix + [UInt8](privateKey.publicKey.rawRepresentation),
      ),
    )
  }
}
