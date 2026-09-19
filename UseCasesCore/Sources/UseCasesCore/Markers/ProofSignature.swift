import Crypto
import Foundation

/// Why a signature did not verify. Each raw value is frozen wire contract and
/// matches the signature-related evidence error code of the same name.
public enum SignatureFailureCode: String, CaseIterable, Equatable, Sendable {
  case signatureMissing = "SIGNATURE_MISSING"
  case signatureAlgorithmUnsupported = "SIGNATURE_ALG_UNSUPPORTED"
  case unknownKeyIdentifier = "UNKNOWN_KEY_ID"
  case badSignature = "BAD_SIGNATURE"
}

/// The outcome of verifying one proof event's signature.
public enum VerifyEventResult: Equatable, Sendable {
  case verified(keyIdentifier: String)
  case failed(code: SignatureFailureCode, message: String)

  /// `{ ok: true, key_id }` or `{ ok: false, code, message }`.
  var jsonValue: JSONValue {
    switch self {
    case let .verified(keyIdentifier):
      .object(JSONObject([("ok", .bool(true)), ("key_id", .string(keyIdentifier))]))
    case let .failed(code, message):
      .object(JSONObject([
        ("ok", .bool(false)),
        ("code", .string(code.rawValue)),
        ("message", .string(message)),
      ]))
    }
  }
}

/// What stops a payload being built or signed at all.
public enum ProofSignatureError: Error, Equatable, Sendable {
  /// The event holds NaN or an infinity, which canonical JSON refuses.
  case nonFiniteNumber
  /// The signing key is not an ed25519 PKCS#8 PEM.
  case invalidPrivateKey
  /// The event is JSON `null`; the TypeScript throws a TypeError reading it.
  case unreadableEvent

  public var code: String {
    switch self {
    case .nonFiniteNumber: "non_finite_number"
    case .invalidPrivateKey: "invalid_private_key"
    case .unreadableEvent: "unreadable_event"
    }
  }

  public var message: String {
    switch self {
    case .nonFiniteNumber: CodeUnitCanonicalJSONError.nonFiniteNumber.message
    case .invalidPrivateKey: "the signing key is not an ed25519 PKCS#8 PEM private key"
    case .unreadableEvent: "Cannot read properties of null (reading 'signature')"
    }
  }
}

/// ed25519 signing and verification for trusted-CI proof events
/// (proofSignature.ts, spec 5.2/5.3).
///
/// The payload is `canonical_json(event without signature)` in UTF-16
/// code-unit key order, as UTF-8 bytes. Signatures are base64; they are READ
/// with node's lenient decoder, so a value node accepts is accepted here.
public enum ProofSignature {
  public static let algorithm = "ed25519"

  /// The canonical signing payload. Any embedded signature is removed first,
  /// so signing and verifying always agree on the bytes.
  public static func signingPayload(_ event: JSONObject) throws(ProofSignatureError) -> String {
    do throws(CodeUnitCanonicalJSONError) {
      return try CodeUnitCanonicalJSON.encode(.object(withoutSignature(event)))
    } catch {
      throw .nonFiniteNumber
    }
  }

  /// The event with a `signature` block appended after its other members; any
  /// signature it already carried is dropped and replaced.
  public static func sign(
    _ event: JSONObject,
    privateKeyPEM: String,
    keyIdentifier: String,
  ) throws(ProofSignatureError) -> JSONObject {
    let payload = try signingPayload(event)
    guard let privateKey = Ed25519PEM.privateKey(fromPEM: privateKeyPEM),
          let signature = try? privateKey.signature(for: Data(payload.utf8))
    else {
      throw .invalidPrivateKey
    }
    var signed = withoutSignature(event)
    signed["signature"] = .object(JSONObject([
      ("alg", .string(algorithm)),
      ("key_id", .string(keyIdentifier)),
      ("value", .string(signature.base64EncodedString())),
    ]))
    return signed
  }

  /// Verify an event's signature against the key its `key_id` resolves to.
  public static func verify(
    _ event: JSONValue,
    resolver: PublicKeyResolver,
  ) throws(ProofSignatureError) -> VerifyEventResult {
    guard event != .null else {
      throw .unreadableEvent
    }
    guard let object = event.objectValue,
          let block = object["signature"]?.objectValue,
          let keyIdentifier = block["key_id"]?.stringValue,
          let value = block["value"]?.stringValue
    else {
      return .failed(
        code: .signatureMissing,
        message: "proof event has no usable signature block (unsigned events are invalid)",
      )
    }
    guard let declared = block["alg"]?.stringValue,
          JavaScriptString.identical(declared, algorithm)
    else {
      let spelled = JavaScriptString.text(of: block["alg"])
      return .failed(
        code: .signatureAlgorithmUnsupported,
        message: "unsupported signature alg: \(spelled) (only ed25519 is allowed)",
      )
    }
    guard let pem = resolver(keyIdentifier, object["created_at"]?.stringValue) else {
      return .failed(
        code: .unknownKeyIdentifier,
        message: "unknown signature key_id: \(keyIdentifier)",
      )
    }
    let payload = try signingPayload(object)
    let signature = NodeBuffer.base64Decode(value)
    guard let publicKey = Ed25519PEM.publicKey(fromPEM: pem),
          publicKey.isValidSignature(signature, for: Data(payload.utf8))
    else {
      return .failed(
        code: .badSignature,
        message: "signature for key_id \(keyIdentifier) did not verify",
      )
    }
    return .verified(keyIdentifier: keyIdentifier)
  }

  private static func withoutSignature(_ event: JSONObject) -> JSONObject {
    var stripped = event
    stripped["signature"] = nil
    return stripped
  }
}
