/// The policy gate (spec 10.2) and the CI-neutral release-gate authority
/// requirement (freshness.ts `evaluatePolicyBlock`, `authoritySatisfies`).
enum FreshnessPolicy {
  /// Is any authority requirement configured? A normalized gate only exists
  /// when one is, but the TypeScript asks again, so this does too.
  static func authorityGateActive(_ gate: WorkspaceReleaseGate?) -> Bool {
    guard let gate else {
      return false
    }
    let requiresContinuousIntegration = gate.requiredAuthority == .continuousIntegration
    return requiresContinuousIntegration || gate.requiresProtectedReference == true
  }

  /// Does the matching proof's `authority` block meet the requirement? Only
  /// its shape is read, never the provider; an absent block satisfies nothing.
  static func authoritySatisfies(
    _ gate: WorkspaceReleaseGate?,
    _ authority: JSONValue?,
  ) -> Bool {
    guard authorityGateActive(gate) else {
      return true
    }
    if gate?.requiredAuthority == .continuousIntegration,
       !JavaScriptValue.strictlyEquals(authority?["type"], "ci")
    {
      return false
    }
    if gate?.requiresProtectedReference == true, authority?["protected_ref"] != .bool(true) {
      return false
    }
    return true
  }

  /// The AUTHORITY_INSUFFICIENT explanation.
  static func authorityReason(
    _ gate: WorkspaceReleaseGate?,
    _ authority: JSONValue?,
  ) -> String {
    var wants: [String] = []
    if gate?.requiredAuthority == .continuousIntegration {
      wants.append(#"authority.type === "ci""#)
    }
    if gate?.requiresProtectedReference == true {
      wants.append("authority.protected_ref === true")
    }
    let got: String
    if JavaScriptValue.isTruthy(authority) {
      let type = JavaScriptValue.text(authority?["type"])
      let protectedReference = JavaScriptValue.text(authority?["protected_ref"] ?? .null)
      got = "type=\(type), protected_ref=\(protectedReference)"
    } else {
      got = "no authority block on the matching proof"
    }
    let required = wants.joined(separator: " and ")
    return "release gate requires \(required), but the matching proof has \(got)"
  }

  /// Whether the row is policy-blocked. `authorityInsufficient` is only true
  /// for a required FRESH row in release mode whose proof falls short.
  static func isBlocked(
    mode: PolicyMode,
    context: PolicyDecisionContext,
    customPolicy: CustomPolicyPredicate?,
    authorityInsufficient: Bool,
  ) -> Bool {
    switch mode {
    case .feature:
      return context.isInvalid
    case .release:
      let required = context.requiredForRelease
      return context.isInvalid
        || (required && context.status != .fresh)
        || (required && context.status == .fresh && authorityInsufficient)
    case .custom:
      guard let customPolicy else {
        return context.isInvalid
      }
      return customPolicy(context)
    }
  }
}
