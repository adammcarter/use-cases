/// Reads a schema-validated keyring value into ``Keyring``. The schema has
/// already guaranteed the shape, so a value that still does not fit reads as
/// nil rather than guessing.
enum KeyringDecoding {
  static func keyring(from value: JSONValue) -> Keyring? {
    guard let entries = value["keys"]?.arrayValue else {
      return nil
    }
    var keys: [KeyringKey] = []
    for entry in entries {
      guard let key = key(from: entry) else {
        return nil
      }
      keys.append(key)
    }
    return Keyring(keys: keys)
  }

  private static func key(from entry: JSONValue) -> KeyringKey? {
    guard let validity = validity(from: entry) else {
      return nil
    }
    switch entry["algorithm"]?.stringValue {
    case "ed25519":
      guard let keyIdentifier = entry["key_id"]?.stringValue,
            let publicKey = entry["public_key"]?.stringValue
      else {
        return nil
      }
      return .ed25519(Ed25519KeyringKey(
        keyIdentifier: keyIdentifier,
        publicKey: publicKey,
        validity: validity,
      ))
    case "webauthn":
      guard let credentialIdentifier = entry["credential_id"]?.stringValue,
            let algorithm = entry["credential_public_key_alg"]?.numberValue,
            let spki = entry["credential_public_key_spki"]?.stringValue
      else {
        return nil
      }
      return .webAuthn(WebAuthnKeyringCredential(
        credentialIdentifier: credentialIdentifier,
        credentialPublicKeyAlgorithm: Int(algorithm),
        credentialPublicKeySPKI: spki,
        validity: validity,
      ))
    default:
      return nil
    }
  }

  private static func validity(from entry: JSONValue) -> KeyringKeyValidity? {
    guard let validFrom = entry["valid_from"]?.stringValue,
          let statusText = entry["status"]?.stringValue,
          let status = KeyringKeyStatus(rawValue: statusText)
    else {
      return nil
    }
    return KeyringKeyValidity(
      validFrom: validFrom,
      validUntil: entry["valid_until"]?.stringValue,
      status: status,
      maxAssuranceTier: entry["max_assurance_tier"]?.stringValue
        .flatMap(KeyringAssuranceTier.init(rawValue:)),
      assuranceTier: entry["assurance_tier"]?.stringValue
        .flatMap(KeyringAssuranceTier.init(rawValue:)),
    )
  }
}
