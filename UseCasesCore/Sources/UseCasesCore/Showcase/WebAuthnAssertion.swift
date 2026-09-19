import Crypto
import Foundation

/// A WebAuthn approval assertion checked against a pinned credential and the
/// live run (`verifyWebAuthnAssertion` in showcase/approvalToken.ts).
///
/// Checked, in order: a complete signature block; a credential the resolver
/// pins for the token's `created_at`; three strict base64url fields; client
/// data that parses to an object with `type` `webauthn.get` and the binding's
/// challenge; authenticator data of at least 37 bytes with the user-present
/// and user-verified flags; and a signature over `authenticatorData ||
/// SHA-256(clientDataJSON)`. The relying party id hash, origin, counter and
/// `crossOrigin` are not checked, as the TypeScript does not check them.
enum WebAuthnAssertion {
  /// The key id a verified assertion reports, and its credential's cap.
  struct Verified {
    let keyIdentifier: String
    let maximumTier: KeyringAssuranceTier
  }

  typealias Failure = ApprovalTokenVerifier.Failure

  static func verify(
    token: JSONValue,
    createdAt: String?,
    resolver: (@Sendable (String, String?) -> WebAuthnCredential?)?,
    liveBinding: JSONValue,
  ) -> Result<Verified, Failure> {
    let block = token["signature"]
    guard ShowcaseJavaScript.isString(block?["alg"], "webauthn"),
          let credentialIdentifier = block?["credential_id"]?.stringValue,
          let authenticatorText = block?["authenticator_data"]?.stringValue,
          let clientDataText = block?["client_data_json"]?.stringValue,
          let signatureText = block?["signature"]?.stringValue
    else {
      return .failure(Failure(
        code: .signatureMissing,
        message: "approval token has no usable webauthn signature block",
      ))
    }

    guard let credential = resolver?(credentialIdentifier, createdAt) else {
      return .failure(Failure(
        code: .webAuthnCredentialUnknown,
        message: "unknown or unpinned webauthn credential_id: \(credentialIdentifier)",
      ))
    }

    let authenticatorData = decodeBase64URL(authenticatorText)
    let clientData = decodeBase64URL(clientDataText)
    let signature = decodeBase64URL(signatureText)
    guard let authenticatorData, let clientData, let signature else {
      return .failure(Failure(
        code: .webAuthnAssertionInvalid,
        message: "webauthn assertion fields must be base64url bytes",
      ))
    }

    if let failure = clientDataFailure(clientData, expectedChallenge: challenge(for: liveBinding)) {
      return .failure(failure)
    }
    if let failure = authenticatorDataFailure(authenticatorData) {
      return .failure(failure)
    }

    let signatureBase = authenticatorData + Array(SHA256.hash(data: clientData))
    guard isValidSignature(signature, over: signatureBase, credential: credential) else {
      return .failure(Failure(
        code: .webAuthnBadSignature,
        message: "webauthn signature for credential_id \(credentialIdentifier) did not verify",
      ))
    }
    return .success(Verified(
      keyIdentifier: credentialIdentifier,
      maximumTier: credential.maxAssuranceTier,
    ))
  }

  /// `approvalBindingChallenge`: base64url of SHA-256 over the binding's
  /// canonical JSON.
  static func challenge(for binding: JSONValue) -> String {
    let canonical = (try? CodeUnitCanonicalJSON.encode(binding)) ?? ""
    return base64URL(Array(SHA256.hash(data: Data(canonical.utf8))))
  }

  /// `decodeBase64Url`: only the URL-safe alphabet, no padding, at least one
  /// byte, and bytes that re-encode to exactly the same text — so stray low
  /// bits in the last character are refused.
  static func decodeBase64URL(_ text: String) -> [UInt8]? {
    guard !text.isEmpty, text.utf8.allSatisfy(isBase64URLCharacter) else {
      return nil
    }
    let bytes = NodeBuffer.base64Decode(text)
    guard !bytes.isEmpty, base64URL(bytes) == text else {
      return nil
    }
    return bytes
  }

  /// `Buffer.toString("base64url")`: URL-safe alphabet, no padding.
  static func base64URL(_ bytes: [UInt8]) -> String {
    Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private static func isBase64URLCharacter(_ byte: UInt8) -> Bool {
    switch byte {
    case UInt8(ascii: "A") ... UInt8(ascii: "Z"), UInt8(ascii: "a") ... UInt8(ascii: "z"),
         UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "-"), UInt8(ascii: "_"):
      true
    default:
      false
    }
  }

  /// `parseWebAuthnClientData`: the bytes read as UTF-8 (invalid sequences
  /// replaced, a byte-order mark kept), parsed, and required to be an object —
  /// an array counts — whose `type` and `challenge` match.
  private static func clientDataFailure(
    _ bytes: [UInt8],
    expectedChallenge: String,
  ) -> Failure? {
    let parsed: JSONValue
    do throws(SchemaError) {
      parsed = try JSONParser.parse(UTF8Text.decodeReplacingInvalid(bytes))
    } catch {
      return Failure(
        code: .webAuthnAssertionInvalid,
        message: "webauthn client_data_json is not valid JSON",
      )
    }
    switch parsed {
    case .object, .array:
      break
    default:
      return Failure(
        code: .webAuthnAssertionInvalid,
        message: "webauthn clientDataJSON is not an object",
      )
    }
    guard ShowcaseJavaScript.isString(parsed.objectValue?["type"], "webauthn.get") else {
      return Failure(
        code: .webAuthnAssertionInvalid,
        message: "webauthn clientDataJSON.type must be webauthn.get",
      )
    }
    guard ShowcaseJavaScript.isString(parsed.objectValue?["challenge"], expectedChallenge) else {
      return Failure(
        code: .webAuthnChallengeMismatch,
        message: "webauthn clientDataJSON.challenge does not match this approval binding",
      )
    }
    return nil
  }

  /// `parseWebAuthnAuthenticatorData`: 37 bytes at least, then the flags byte
  /// at offset 32 must carry user presence (0x01) and user verification (0x04).
  private static func authenticatorDataFailure(_ bytes: [UInt8]) -> Failure? {
    guard bytes.count >= 37 else {
      return Failure(
        code: .webAuthnAssertionInvalid,
        message: "webauthn authenticator_data is too short",
      )
    }
    let flags = bytes[32]
    if flags & 0x01 == 0 {
      return Failure(
        code: .webAuthnUserNotPresent,
        message: "webauthn assertion did not set the UP flag",
      )
    }
    if flags & 0x04 == 0 {
      return Failure(
        code: .webAuthnUserNotVerified,
        message: "webauthn assertion did not set the UV flag",
      )
    }
    return nil
  }

  /// `verifyWebAuthnSignature`: node builds the key from the SPKI, then
  /// verifies with digest `SHA256` when the declared COSE alg is -7 and with
  /// the key type's default otherwise. So the KEY TYPE decides, not the alg:
  ///
  /// - an EC key on P-256, P-384 or P-521 verifies a DER-encoded ECDSA
  ///   signature over SHA-256 whatever the declared alg, as SHA-256 is
  ///   OpenSSL's default digest for EC keys;
  /// - an Ed25519 key verifies a pure Ed25519 signature, except under alg -7,
  ///   where node throws on the digest and the TypeScript answers false.
  ///
  /// Every other key type node would accept — RSA, RSA-PSS, DSA, secp256k1,
  /// Ed448 — has no implementation in swift-crypto and is refused here, where
  /// node would verify it. The keyring schema declares alg -7 or -8 only, so
  /// such a key reaches this check only when its entry's SPKI does not match
  /// its declared alg.
  static func isValidSignature(
    _ signature: [UInt8],
    over signatureBase: [UInt8],
    credential: WebAuthnCredential,
  ) -> Bool {
    guard let spki = decodeBase64URL(credential.credentialPublicKeySPKI) else {
      return false
    }
    let digest = SHA256.hash(data: signatureBase)
    if let key = try? P256.Signing.PublicKey(derRepresentation: spki) {
      guard let parsed = try? P256.Signing.ECDSASignature(derRepresentation: signature) else {
        return false
      }
      return key.isValidSignature(parsed, for: digest)
    }
    if let key = try? P384.Signing.PublicKey(derRepresentation: spki) {
      guard let parsed = try? P384.Signing.ECDSASignature(derRepresentation: signature) else {
        return false
      }
      return key.isValidSignature(parsed, for: digest)
    }
    if let key = try? P521.Signing.PublicKey(derRepresentation: spki) {
      guard let parsed = try? P521.Signing.ECDSASignature(derRepresentation: signature) else {
        return false
      }
      return key.isValidSignature(parsed, for: digest)
    }
    let prefix = Ed25519PEM.publicKeyPrefix
    guard spki.count == prefix.count + 32, spki.starts(with: prefix),
          let key = try? Curve25519.Signing
          .PublicKey(rawRepresentation: spki.dropFirst(prefix.count))
    else {
      return false
    }
    return credential.credentialPublicKeyAlgorithm != -7
      && key.isValidSignature(signature, for: signatureBase)
  }
}
