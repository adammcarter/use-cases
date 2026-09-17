/// Why an approval token did not verify. Each raw value is frozen wire text.
public enum ApprovalTokenFailureCode: String, CaseIterable, Sendable {
  case signatureMissing = "SIGNATURE_MISSING"
  case signatureAlgorithmUnsupported = "SIGNATURE_ALG_UNSUPPORTED"
  case unknownKeyIdentifier = "UNKNOWN_KEY_ID"
  case badSignature = "BAD_SIGNATURE"
  case bindingMismatch = "BINDING_MISMATCH"
  case tokenExpired = "TOKEN_EXPIRED"
  case nonceBurned = "NONCE_BURNED"
  case assuranceOverClaim = "ASSURANCE_OVER_CLAIM"
  case assuranceTooLow = "ASSURANCE_TOO_LOW"
  case webAuthnCredentialUnknown = "WEBAUTHN_CREDENTIAL_UNKNOWN"
  case webAuthnAssertionInvalid = "WEBAUTHN_ASSERTION_INVALID"
  case webAuthnChallengeMismatch = "WEBAUTHN_CHALLENGE_MISMATCH"
  case webAuthnUserNotPresent = "WEBAUTHN_USER_NOT_PRESENT"
  case webAuthnUserNotVerified = "WEBAUTHN_USER_NOT_VERIFIED"
  case webAuthnBadSignature = "WEBAUTHN_BAD_SIGNATURE"
  case malformedToken = "MALFORMED_TOKEN"
}

/// `VerifyApprovalTokenResult`.
public enum ApprovalTokenVerification: Equatable, Sendable {
  /// `decision` is the token's own string, unchecked beyond being a string.
  case verified(jti: String, decision: String, keyIdentifier: String, assuranceTier: AssuranceTier)
  case failed(code: ApprovalTokenFailureCode, message: String)

  /// `{ ok: true, jti, decision, key_id, assurance_tier }` or
  /// `{ ok: false, code, message }`.
  public var jsonValue: JSONValue {
    switch self {
    case let .verified(jti, decision, keyIdentifier, assuranceTier):
      .object(JSONObject([
        ("ok", .bool(true)),
        ("jti", .string(jti)),
        ("decision", .string(decision)),
        ("key_id", .string(keyIdentifier)),
        ("assurance_tier", .string(assuranceTier.rawValue)),
      ]))
    case let .failed(code, message):
      .object(JSONObject([
        ("ok", .bool(false)),
        ("code", .string(code.rawValue)),
        ("message", .string(message)),
      ]))
    }
  }
}

/// Minting, signing and assembling approval requests and tokens
/// (showcase/approvalToken.ts). Requests, tokens and assertions are JSON
/// objects, as the CLI reads them from files: members are copied in the
/// TypeScript's order, and a member the source lacks is left out.
public struct ApprovalTokens: Sendable {
  let clock: any ShowcaseClock
  let uuidSource: any ShowcaseUUIDSource

  public init(
    clock: any ShowcaseClock = SystemShowcaseClock(),
    uuidSource: any ShowcaseUUIDSource = SystemShowcaseUUIDSource(),
  ) {
    self.clock = clock
    self.uuidSource = uuidSource
  }

  /// `mintApprovalRequest`: the binding copied, a plugin-minted nonce unless
  /// one is given, issued now (the clock unless given) and expiring
  /// `ttlMinutes` (15 unless given) later.
  public func mintRequest(
    binding: JSONObject,
    nowMilliseconds: Double? = nil,
    ttlMinutes: Double? = nil,
    jti: String? = nil,
  ) throws(ShowcaseError) -> JSONObject {
    let now = nowMilliseconds ?? clock.now()
    let ttl = ttlMinutes ?? 15
    let nonce = jti ?? "approval.\(uuidSource.randomUUID())"
    return try JSONObject([
      ("approval_request_schema", .string("ucase-approval-request-v1")),
      ("binding", .object(binding)),
      ("jti", .string(nonce)),
      ("iat", .string(Self.isoString(milliseconds: now))),
      ("exp", .string(Self.isoString(milliseconds: now + ttl * 60000))),
    ])
  }

  /// `new Date(milliseconds).toISOString()`, which throws a RangeError for a
  /// time value outside JavaScript's range.
  private static func isoString(milliseconds: Double) throws(ShowcaseError) -> String {
    guard milliseconds.isFinite, abs(milliseconds.rounded(.towardZero)) <= 8.64e15 else {
      throw .invalidTimeValue
    }
    return JavaScriptTimestamp.isoString(milliseconds: milliseconds.rounded(.towardZero))
  }

  /// `signApprovalToken`: the request's facts, `created_at` equal to `iat`,
  /// the decision and any claimed method with the tier it fixes, signed with
  /// ed25519 over its canonical form.
  public static func sign(
    request: JSONObject,
    decision: String,
    privateKeyPEM: String,
    keyIdentifier: String,
    assuranceMethod: String? = nil,
  ) throws(ShowcaseError) -> JSONObject {
    if let assuranceMethod, JavaScriptString.identical(
      assuranceMethod,
      AssuranceMethod.webAuthn.rawValue,
    ) {
      throw .webAuthnAssuranceOnEd25519Token
    }
    var unsigned = tokenFacts(request: request, decision: decision)
    if let assuranceMethod {
      // The CLI passes the flag's text through unchecked: a method the ladder
      // does not know has no tier, and the member is left out.
      unsigned["assurance_method"] = .string(assuranceMethod)
      let method = AssuranceMethod.recognised(.string(assuranceMethod))
      unsigned["assurance_tier"] = method.map { method in
        .string(method.tier.rawValue)
      }
    }
    do throws(ProofSignatureError) {
      return try ProofSignature.sign(
        unsigned,
        privateKeyPEM: privateKeyPEM,
        keyIdentifier: keyIdentifier,
      )
    } catch {
      throw error == .invalidPrivateKey ? .invalidPrivateKey : .unsupportedCanonicalValue
    }
  }

  /// `buildWebAuthnApprovalToken`: the request's facts, WebAuthn assurance,
  /// and the four assertion members under `alg: "webauthn"`.
  public static func buildWebAuthnToken(
    request: JSONObject,
    decision: String,
    assertion: JSONObject,
  ) -> JSONObject {
    var token = tokenFacts(request: request, decision: decision)
    token["assurance_method"] = .string(AssuranceMethod.webAuthn.rawValue)
    token["assurance_tier"] = .string(AssuranceTier.webAuthnHardware.rawValue)
    var signature = JSONObject([("alg", .string("webauthn"))])
    for key in ["credential_id", "authenticator_data", "client_data_json", "signature"] {
      signature[key] = assertion[key]
    }
    token["signature"] = .object(signature)
    return token
  }

  private static func tokenFacts(
    request: JSONObject,
    decision: String,
  ) -> JSONObject {
    var token = JSONObject([
      ("approval_token_schema", .string("ucase-approval-token-v1")),
      ("binding", .object(ShowcaseJavaScript.spread(request["binding"]))),
    ])
    token["jti"] = request["jti"]
    token["iat"] = request["iat"]
    token["exp"] = request["exp"]
    token["created_at"] = request["iat"]
    token["decision"] = .string(decision)
    return token
  }
}
