/// The verified facts of a trusted user approval or rejection.
struct TrustedUserDecision {
  let jti: String
  let actorType: JSONValue?
  let assuranceTier: AssuranceTier
  let decision: String
  let keyIdentifier: String
}

/// Whether a recorded user decision counts as a genuine human sign-off, decided
/// ONLY by re-verifying the signed token embedded in it
/// (showcase/approvalAuthority.ts).
struct ApprovalTrust {
  let resolvers: ShowcaseTrustResolvers
  /// The plan's floor; host user presence when nil.
  let assuranceFloor: AssuranceTier?

  /// `embeddedApprovalToken`: the payload's `approval_token`, when it is an
  /// object declaring the token schema.
  static func embeddedToken(_ event: JSONValue) throws(ShowcaseError) -> JSONValue? {
    let token = try ShowcaseJavaScript.member(
      ShowcaseJavaScript.member(event, "payload"),
      "approval_token",
    )
    guard case .object = token,
          ShowcaseJavaScript.isString(token?["approval_token_schema"], "ucase-approval-token-v1")
    else {
      return nil
    }
    return token
  }

  /// `trustedUserDecisionMetadata`: a user's approval or rejection whose token
  /// verifies against the resolvers — never burned, checked at its own `iat`,
  /// against its own binding, at the plan's floor when a tier resolver can
  /// place the key and at the weakest tier when none can.
  func trustedDecision(_ event: JSONValue) throws(ShowcaseError) -> TrustedUserDecision? {
    let actorType = try ShowcaseJavaScript.member(event, "actor_type")
    guard ShowcaseJavaScript.isString(actorType, ShowcaseActorType.user.rawValue) else {
      return nil
    }
    let type = try ShowcaseJavaScript.member(event, "event_type")
    guard ShowcaseJavaScript.isString(type, "approval_recorded")
      || ShowcaseJavaScript.isString(type, "approval_rejected")
    else {
      return nil
    }
    guard let token = try Self.embeddedToken(event), resolvers.publicKeyResolver != nil else {
      return nil
    }
    let floor: AssuranceTier = resolvers.tierResolver == nil
      ? .untrustedAutomation
      : assuranceFloor ?? .trustedHostUserPresence
    let issuedAt = JavaScriptDate.parse(JavaScriptString.text(of: token["iat"])) ?? .nan
    let result = ApprovalTokenVerifier.verify(ApprovalTokenVerificationOptions(
      token: token,
      resolvers: resolvers,
      liveBinding: token["binding"] ?? .null,
      isNonceBurned: { _ in false },
      nowMilliseconds: issuedAt,
      assuranceFloor: floor,
    ))
    guard case let .verified(jti, decision, keyIdentifier, assuranceTier) = result else {
      return nil
    }
    return TrustedUserDecision(
      jti: jti,
      actorType: actorType,
      assuranceTier: assuranceTier,
      decision: decision,
      keyIdentifier: keyIdentifier,
    )
  }

  /// `isTrustedUserDecisionEvent`: anything but a user's approval or rejection
  /// is governed elsewhere and counts; a user's counts only when verified.
  func isTrustedDecisionEvent(_ event: JSONValue) throws(ShowcaseError) -> Bool {
    let actorType = try ShowcaseJavaScript.member(event, "actor_type")
    guard ShowcaseJavaScript.isString(actorType, ShowcaseActorType.user.rawValue) else {
      return true
    }
    let type = try ShowcaseJavaScript.member(event, "event_type")
    guard ShowcaseJavaScript.isString(type, "approval_recorded")
      || ShowcaseJavaScript.isString(type, "approval_rejected")
    else {
      return true
    }
    return try trustedDecision(event) != nil
  }
}
