/// What `verifyApprovalToken` checks a token against.
public struct ApprovalTokenVerificationOptions: Sendable {
  /// The token as parsed: any JSON value, or absent.
  public let token: JSONValue?
  public let resolvers: ShowcaseTrustResolvers
  /// The live run's facts, read member by member as JavaScript would.
  public let liveBinding: JSONValue
  public let isNonceBurned: @Sendable (String) -> Bool
  /// The instant to check expiry at; the clock's when nil. NaN is kept.
  public let nowMilliseconds: Double?
  public let assuranceFloor: AssuranceTier

  public init(
    token: JSONValue?,
    resolvers: ShowcaseTrustResolvers,
    liveBinding: JSONValue,
    isNonceBurned: @escaping @Sendable (String) -> Bool,
    nowMilliseconds: Double?,
    assuranceFloor: AssuranceTier,
  ) {
    self.token = token
    self.resolvers = resolvers
    self.liveBinding = liveBinding
    self.isNonceBurned = isNonceBurned
    self.nowMilliseconds = nowMilliseconds
    self.assuranceFloor = assuranceFloor
  }
}

/// `verifyApprovalToken`: signature and key first, then binding, expiry,
/// single use and assurance tier, in that order.
public enum ApprovalTokenVerifier {
  static let bindingFields = [
    "run_id",
    "finish_event_id",
    "plan_content_hash",
    "ledger_head_hash",
    "evidence_digest",
    "git_commit",
    "ci_freshness_digest",
  ]

  public static func verify(
    _ options: ApprovalTokenVerificationOptions,
    clock: any ShowcaseClock = SystemShowcaseClock(),
  ) -> ApprovalTokenVerification {
    guard JavaScriptValue.isTruthy(options.token), let token = options.token,
          ShowcaseJavaScript.isString(token["approval_token_schema"], "ucase-approval-token-v1"),
          let jti = token["jti"]?.stringValue, !jti.isEmpty,
          JavaScriptValue.isTruthy(token["binding"]),
          let decision = token["decision"]?.stringValue
    else {
      return .failed(code: .malformedToken, message: "approval token is malformed")
    }

    let signed: SignedBy
    switch signer(of: token, options) {
    case let .failure(failure):
      return failure.verification
    case let .success(value):
      signed = value
    }

    if let mismatch = bindingMismatch(token["binding"], options.liveBinding) {
      return mismatch
    }

    let now = options.nowMilliseconds ?? clock.now()
    let expiry = JavaScriptDate.parse(JavaScriptString.text(of: token["exp"]))
    guard let expiry, !(now > expiry) else {
      return .failed(code: .tokenExpired, message: "approval token has expired")
    }

    if options.isNonceBurned(jti) {
      return .failed(code: .nonceBurned, message: "approval token nonce already burned (replay)")
    }

    if let refusal = tierRefusal(signed, floor: options.assuranceFloor) {
      return refusal
    }
    return .verified(
      jti: jti,
      decision: decision,
      keyIdentifier: signed.keyIdentifier,
      assuranceTier: signed.tier,
    )
  }

  /// Every bound field compared with `!==`, in the TypeScript's field order.
  private static func bindingMismatch(
    _ tokenBinding: JSONValue?,
    _ liveBinding: JSONValue,
  ) -> ApprovalTokenVerification? {
    for field in bindingFields {
      let tokenValue = ShowcaseJavaScript.optionalMember(tokenBinding, field)
      let liveValue = ShowcaseJavaScript.optionalMember(liveBinding, field)
      guard !strictlyEqual(tokenValue, liveValue) else {
        continue
      }
      return .failed(
        code: .bindingMismatch,
        message: "approval token binding.\(field) does not match the live run",
      )
    }
    return nil
  }

  /// The claimed tier capped by the key's maximum, then held to the floor.
  private static func tierRefusal(
    _ signed: SignedBy,
    floor: AssuranceTier,
  ) -> ApprovalTokenVerification? {
    guard signed.maximumTier.meets(signed.tier) else {
      return .failed(
        code: .assuranceOverClaim,
        message: "approval token claims assurance tier \(signed.tier.rawValue) above key "
          + "\(signed.keyIdentifier) cap \(signed.maximumTier.rawValue)",
      )
    }
    guard signed.tier.meets(floor) else {
      return .failed(
        code: .assuranceTooLow,
        message: "approval token assurance tier \(signed.tier.rawValue) does not meet floor "
          + "\(floor.rawValue)",
      )
    }
    return nil
  }

  /// The key that signed, the cap its keyring entry allows, and the tier the
  /// token claims.
  struct SignedBy {
    let keyIdentifier: String
    let maximumTier: AssuranceTier
    let tier: AssuranceTier
  }

  struct Failure: Error {
    let code: ApprovalTokenFailureCode
    let message: String

    var verification: ApprovalTokenVerification {
      .failed(code: code, message: message)
    }
  }

  private static func signer(
    of token: JSONValue,
    _ options: ApprovalTokenVerificationOptions,
  ) -> Result<SignedBy, Failure> {
    let createdAt = token["created_at"].map { value in
      JavaScriptString.text(of: value)
    }
    if ShowcaseJavaScript.isString(
      ShowcaseJavaScript.optionalMember(token["signature"], "alg"),
      "webauthn",
    ) {
      let assertion = WebAuthnAssertion.verify(
        token: token,
        createdAt: createdAt,
        resolver: options.resolvers.webAuthnCredentialResolver,
        liveBinding: options.liveBinding,
      )
      return assertion.flatMap { credential in
        claimedWebAuthnTier(token).map { tier in
          SignedBy(
            keyIdentifier: credential.keyIdentifier,
            maximumTier: AssuranceTier.normalized(credential.maximumTier),
            tier: tier,
          )
        }
      }
    }

    let result: VerifyEventResult
    do throws(ProofSignatureError) {
      result = try ProofSignature.verify(
        token,
        resolver: options.resolvers.publicKeyResolver ?? { _, _ in nil },
      )
    } catch {
      return .failure(Failure(code: .malformedToken, message: error.message))
    }
    switch result {
    case let .failed(code, message):
      return .failure(Failure(
        code: ApprovalTokenFailureCode(rawValue: code.rawValue) ?? .badSignature,
        message: message,
      ))
    case let .verified(keyIdentifier):
      let maximumTier = AssuranceTier.normalized(options.resolvers.tierResolver?(
        keyIdentifier,
        createdAt,
      ))
      return claimedEd25519Tier(token, maximumTier: maximumTier).map { tier in
        SignedBy(keyIdentifier: keyIdentifier, maximumTier: maximumTier, tier: tier)
      }
    }
  }

  /// `claimedAssuranceTier`: no method claims the key's cap; otherwise a known,
  /// non-WebAuthn method whose tier is present and the one the method fixes.
  private static func claimedEd25519Tier(
    _ token: JSONValue,
    maximumTier: AssuranceTier,
  ) -> Result<AssuranceTier, Failure> {
    guard let methodValue = token["assurance_method"] else {
      return .success(maximumTier)
    }
    guard let method = AssuranceMethod.recognised(methodValue) else {
      return malformed("unsupported assurance_method \(JavaScriptString.text(of: methodValue))")
    }
    if method == .webAuthn {
      return malformed("ed25519 signatures cannot claim webauthn assurance")
    }
    guard let claimed = token["assurance_tier"]?.stringValue.flatMap(AssuranceTier.recognised)
    else {
      return malformed("approval token assurance_tier is missing or unsupported")
    }
    guard claimed == method.tier else {
      return malformed(
        "approval token assurance_tier \(claimed.rawValue) does not match method "
          + method.rawValue,
      )
    }
    return .success(claimed)
  }

  /// `claimedWebAuthnAssuranceTier`: no claim at all is hardware; any claim
  /// must be exactly the WebAuthn method and hardware tier.
  private static func claimedWebAuthnTier(_ token: JSONValue) -> Result<AssuranceTier, Failure> {
    let method = token["assurance_method"]
    let tier = token["assurance_tier"]
    if method == nil, tier == nil {
      return .success(.webAuthnHardware)
    }
    guard ShowcaseJavaScript.isString(method, AssuranceMethod.webAuthn.rawValue) else {
      return malformed("webauthn signature must use assurance_method webauthn")
    }
    guard ShowcaseJavaScript.isString(tier, AssuranceTier.webAuthnHardware.rawValue) else {
      return malformed("webauthn signature must use assurance_tier webauthn_hardware")
    }
    return .success(.webAuthnHardware)
  }

  private static func malformed(_ message: String) -> Result<AssuranceTier, Failure> {
    .failure(Failure(code: .malformedToken, message: message))
  }

  /// `left !== right` negated, for two values read off parsed JSON: equal
  /// primitives, or both absent. Two objects or arrays are never equal.
  private static func strictlyEqual(
    _ left: JSONValue?,
    _ right: JSONValue?,
  ) -> Bool {
    switch (left, right) {
    case (.none, .none), (.null, .null):
      true
    case let (.bool(leftFlag), .bool(rightFlag)):
      leftFlag == rightFlag
    case let (.number(leftNumber), .number(rightNumber)):
      leftNumber == rightNumber
    case let (.string(leftText), .string(rightText)):
      JavaScriptString.identical(leftText, rightText)
    default:
      false
    }
  }
}
