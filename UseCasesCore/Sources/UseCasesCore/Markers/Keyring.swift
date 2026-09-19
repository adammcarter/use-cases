import Foundation

/// Maps a signature's key id to the public key PEM that verifies it, or nil
/// when the key id is unknown — or, for a keyring, revoked or outside its
/// validity window — which makes the proof INVALID (spec 5.3 rule 2; fail
/// closed). `createdAt` is the proof event's own `created_at` when it has one.
public typealias PublicKeyResolver = @Sendable (
  _ keyIdentifier: String,
  _ createdAt: String?,
) -> String?

/// The highest human-approval assurance tier a key may assert.
public enum KeyringAssuranceTier: String, Equatable, Sendable {
  case untrustedAutomation = "untrusted_automation"
  case sameChannelOperatorConfirmation = "same_channel_operator_confirmation"
  case trustedHostUserPresence = "trusted_host_user_presence"
  case webAuthnHardware = "webauthn_hardware"
}

public enum KeyringKeyStatus: String, Equatable, Sendable {
  case active
  case revoked
}

/// What every keyring entry carries: a validity window, a status and an
/// optional assurance cap (with its legacy alias).
public struct KeyringKeyValidity: Equatable, Sendable {
  public let validFrom: String
  public let validUntil: String?
  public let status: KeyringKeyStatus
  public let maxAssuranceTier: KeyringAssuranceTier?
  public let assuranceTier: KeyringAssuranceTier?

  public init(
    validFrom: String,
    validUntil: String?,
    status: KeyringKeyStatus,
    maxAssuranceTier: KeyringAssuranceTier? = nil,
    assuranceTier: KeyringAssuranceTier? = nil,
  ) {
    self.validFrom = validFrom
    self.validUntil = validUntil
    self.status = status
    self.maxAssuranceTier = maxAssuranceTier
    self.assuranceTier = assuranceTier
  }

  /// The cap, preferring the current field over its legacy alias, and never
  /// trusting by omission.
  var effectiveMaxAssuranceTier: KeyringAssuranceTier {
    maxAssuranceTier ?? assuranceTier ?? .untrustedAutomation
  }
}

/// An ed25519 signing key's public half.
public struct Ed25519KeyringKey: Equatable, Sendable {
  public let keyIdentifier: String
  public let publicKey: String
  public let validity: KeyringKeyValidity

  public init(
    keyIdentifier: String,
    publicKey: String,
    validity: KeyringKeyValidity,
  ) {
    self.keyIdentifier = keyIdentifier
    self.publicKey = publicKey
    self.validity = validity
  }
}

/// A pinned WebAuthn credential.
public struct WebAuthnKeyringCredential: Equatable, Sendable {
  public let credentialIdentifier: String
  /// The COSE algorithm: ES256 is -7, EdDSA is -8.
  public let credentialPublicKeyAlgorithm: Int
  public let credentialPublicKeySPKI: String
  public let validity: KeyringKeyValidity

  public init(
    credentialIdentifier: String,
    credentialPublicKeyAlgorithm: Int,
    credentialPublicKeySPKI: String,
    validity: KeyringKeyValidity,
  ) {
    self.credentialIdentifier = credentialIdentifier
    self.credentialPublicKeyAlgorithm = credentialPublicKeyAlgorithm
    self.credentialPublicKeySPKI = credentialPublicKeySPKI
    self.validity = validity
  }
}

public enum KeyringKey: Equatable, Sendable {
  case ed25519(Ed25519KeyringKey)
  case webAuthn(WebAuthnKeyringCredential)
}

/// What a WebAuthn credential resolves to.
public struct WebAuthnCredential: Equatable, Sendable {
  public let credentialIdentifier: String
  public let credentialPublicKeyAlgorithm: Int
  public let credentialPublicKeySPKI: String
  public let maxAssuranceTier: KeyringAssuranceTier

  /// `{ credential_id, credential_public_key_alg, credential_public_key_spki,
  /// max_assurance_tier }`.
  var jsonValue: JSONValue {
    .object(JSONObject([
      ("credential_id", .string(credentialIdentifier)),
      ("credential_public_key_alg", .number(Double(credentialPublicKeyAlgorithm))),
      ("credential_public_key_spki", .string(credentialPublicKeySPKI)),
      ("max_assurance_tier", .string(maxAssuranceTier.rawValue)),
    ]))
  }
}

/// Why a keyring could not be loaded. The codes are the TypeScript's.
public enum KeyringError: Error, Equatable, Sendable {
  case schemaInvalid(message: String)
  case unreadable(message: String)
  case invalidJSON(message: String)

  public var code: String {
    switch self {
    case .schemaInvalid: "keyring_schema_invalid"
    case .unreadable: "keyring_unreadable"
    case .invalidJSON: "keyring_invalid_json"
    }
  }

  public var message: String {
    switch self {
    case let .schemaInvalid(message), let .unreadable(message), let .invalidJSON(message):
      message
    }
  }
}

/// The opt-in multi-key public-key registry (keyring.ts): several keys, each
/// with a validity window and a revocation status, so keys rotate and retire
/// without a code change.
///
/// Every resolver is FAIL-CLOSED: a key resolves only when it exists, is
/// active, and the proof's `created_at` falls inside its window.
public struct Keyring: Equatable, Sendable {
  public static let schemaIdentifier = "https://use-cases.dev/schemas/v1/keyring.schema.json"

  public let keys: [KeyringKey]

  public init(keys: [KeyringKey]) {
    self.keys = keys
  }

  private static let registry: SchemaRegistry? = try? SchemaRegistry()

  /// Schema-validate and read a keyring value.
  public static func parse(
    _ value: JSONValue,
    sourcePath: String?,
  ) throws(KeyringError) -> Keyring {
    let result = registry?.validate(
      schemaIdentifier: schemaIdentifier,
      value: value,
      sourcePath: sourcePath,
    )
    guard let result, result.isValid, let keyring = KeyringDecoding.keyring(from: value) else {
      let details = (result?.diagnostics ?? [])
        .map { diagnostic in
          JavaScriptString.trim("\(diagnostic.jsonPointer ?? "") \(diagnostic.message)")
        }
        .joined(separator: "; ")
      throw .schemaInvalid(message: "keyring file is not a valid keyring: \(details)")
    }
    return keyring
  }

  /// Read, JSON-parse and schema-validate a keyring file.
  public static func load(filePath: String) throws(KeyringError) -> Keyring {
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: filePath)
    } catch {
      throw .unreadable(message: "could not read keyring file \(filePath): \(error.message)")
    }
    let value: JSONValue
    do throws(SchemaError) {
      value = try JSONParser.parse(text)
    } catch {
      throw .invalidJSON(message: "keyring file \(filePath) is not valid JSON: \(error.message)")
    }
    return try parse(value, sourcePath: filePath)
  }

  /// Load a keyring file and build its public-key resolver.
  public static func publicKeyResolver(fromFile filePath: String) throws(KeyringError)
    -> PublicKeyResolver
  {
    try load(filePath: filePath).publicKeyResolver()
  }

  /// A validated keyring file's `keys` as the JSON they were read from, for a
  /// caller that merges several sources before re-parsing them — what the
  /// CLI's `approval_trust` anchor does with `loadKeyring(path).keys`. The
  /// failures, and their wording, are ``load(filePath:)``'s.
  public static func loadKeys(filePath: String) throws(KeyringError) -> [JSONValue] {
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: filePath)
    } catch {
      throw .unreadable(message: "could not read keyring file \(filePath): \(error.message)")
    }
    let value: JSONValue
    do throws(SchemaError) {
      value = try JSONParser.parse(text)
    } catch {
      throw .invalidJSON(message: "keyring file \(filePath) is not valid JSON: \(error.message)")
    }
    _ = try parse(value, sourcePath: filePath)
    return value["keys"]?.arrayValue ?? []
  }

  /// A key id resolves to its PEM only when active and in-window at `createdAt`.
  public func publicKeyResolver() -> PublicKeyResolver {
    let index = ed25519Index()
    return { keyIdentifier, createdAt in
      Self.activeInWindow(index[CodeUnitKey(keyIdentifier)], at: createdAt)?.publicKey
    }
  }

  /// The key's assurance cap under the same gate. A key that would not verify
  /// a signature never lends its cap either, and hardware assurance is never
  /// granted to an ed25519 signer.
  public func maxAssuranceTierResolver() -> @Sendable (String, String?) -> KeyringAssuranceTier? {
    let index = ed25519Index()
    return { keyIdentifier, createdAt in
      guard let key = Self.activeInWindow(index[CodeUnitKey(keyIdentifier)], at: createdAt) else {
        return nil
      }
      let tier = key.validity.effectiveMaxAssuranceTier
      return tier == .webAuthnHardware ? .untrustedAutomation : tier
    }
  }

  /// A credential id resolves only when pinned here, active and in-window.
  public func webAuthnCredentialResolver() -> @Sendable (String, String?) -> WebAuthnCredential? {
    let index = credentialIndex()
    return { credentialIdentifier, createdAt in
      guard let credential = Self.activeInWindow(
        index[CodeUnitKey(credentialIdentifier)],
        at: createdAt,
      ), [-7, -8].contains(credential.credentialPublicKeyAlgorithm)
      else {
        return nil
      }
      return WebAuthnCredential(
        credentialIdentifier: credential.credentialIdentifier,
        credentialPublicKeyAlgorithm: credential.credentialPublicKeyAlgorithm,
        credentialPublicKeySPKI: credential.credentialPublicKeySPKI,
        maxAssuranceTier: credential.validity.effectiveMaxAssuranceTier,
      )
    }
  }

  /// First entry per key id wins; later duplicates are ignored. Keyed by code
  /// unit: `key_id` has no pattern in the schema, so two canonically equivalent
  /// ids are two different keys, exactly as they are in a JavaScript `Map`.
  private func ed25519Index() -> [CodeUnitKey: Ed25519KeyringKey] {
    var index: [CodeUnitKey: Ed25519KeyringKey] = [:]
    for case let .ed25519(key) in keys where index[CodeUnitKey(key.keyIdentifier)] == nil {
      index[CodeUnitKey(key.keyIdentifier)] = key
    }
    return index
  }

  private func credentialIndex() -> [CodeUnitKey: WebAuthnKeyringCredential] {
    var index: [CodeUnitKey: WebAuthnKeyringCredential] = [:]
    for case let .webAuthn(credential) in keys
      where index[CodeUnitKey(credential.credentialIdentifier)] == nil
    {
      index[CodeUnitKey(credential.credentialIdentifier)] = credential
    }
    return index
  }

  private static func activeInWindow<Key: KeyringEntry>(
    _ key: Key?,
    at createdAt: String?,
  ) -> Key? {
    guard let key, key.validity.status == .active,
          let createdAt, let moment = JavaScriptDate.parse(createdAt),
          let from = JavaScriptDate.parse(key.validity.validFrom), moment >= from
    else {
      return nil
    }
    if let validUntil = key.validity.validUntil {
      guard let until = JavaScriptDate.parse(validUntil), moment <= until else {
        return nil
      }
    }
    return key
  }
}

protocol KeyringEntry {
  var validity: KeyringKeyValidity { get }
}

extension Ed25519KeyringKey: KeyringEntry {}
extension WebAuthnKeyringCredential: KeyringEntry {}
