/// How strongly an approval proves a real human signed it off
/// (showcase/approvalTiers.ts), ordered weakest to strongest.
public enum AssuranceTier: String, CaseIterable, Comparable, Sendable {
  /// An automated or in-session signer; never a human sign-off.
  case untrustedAutomation = "untrusted_automation"
  /// An operator confirming on the agent's own channel; agent-spoofable.
  case sameChannelOperatorConfirmation = "same_channel_operator_confirmation"
  /// A keyring-verified key held in host custody outside the agent's scope.
  case trustedHostUserPresence = "trusted_host_user_presence"
  /// A WebAuthn assertion verified against a pinned hardware credential.
  case webAuthnHardware = "webauthn_hardware"

  /// The ladder rank, weakest first.
  private var rank: Int {
    Self.allCases.firstIndex(of: self) ?? 0
  }

  public static func < (
    left: AssuranceTier,
    right: AssuranceTier,
  ) -> Bool {
    left.rank < right.rank
  }

  /// `normalizeAssuranceTier`: anything unrecognised, absent included, is the
  /// weakest tier.
  static func normalized(_ value: JSONValue?) -> AssuranceTier {
    value?.stringValue.flatMap(recognised) ?? .untrustedAutomation
  }

  /// `normalizeAssuranceTier` for a keyring cap.
  static func normalized(_ tier: KeyringAssuranceTier?) -> AssuranceTier {
    let cap = tier.flatMap { tier in
      AssuranceTier(rawValue: tier.rawValue)
    }
    return cap ?? .untrustedAutomation
  }

  /// `isAssuranceTier`: a string spelling exactly one of the tiers.
  static func recognised(_ text: String) -> AssuranceTier? {
    allCases.first { tier in
      JavaScriptString.identical(tier.rawValue, text)
    }
  }

  /// `tierMeetsFloor`.
  func meets(_ floor: AssuranceTier) -> Bool {
    self >= floor
  }

  /// `trustedForHumanSignoff`: at or above host user presence.
  public var isTrustedForHumanSignOff: Bool {
    meets(.trustedHostUserPresence)
  }
}

/// How an approval was actually captured; each fixes the tier it may claim.
public enum AssuranceMethod: String, CaseIterable, Sendable {
  case automation
  case sameChannel = "same_channel"
  case operatingSystemPresence = "os_presence"
  case webAuthn = "webauthn"

  /// `ASSURANCE_METHOD_TO_TIER`.
  public var tier: AssuranceTier {
    switch self {
    case .automation: .untrustedAutomation
    case .sameChannel: .sameChannelOperatorConfirmation
    case .operatingSystemPresence: .trustedHostUserPresence
    case .webAuthn: .webAuthnHardware
    }
  }

  /// `isAssuranceMethod`.
  static func recognised(_ value: JSONValue?) -> AssuranceMethod? {
    guard let text = value?.stringValue else {
      return nil
    }
    return allCases.first { method in
      JavaScriptString.identical(method.rawValue, text)
    }
  }
}

/// The approval floor a plan's policies set (showcase/approvalPolicy.ts).
enum ApprovalPolicy {
  /// `approvalAssuranceFloorForPlan`: the strongest `minimum_assurance_tier`
  /// among the policies that require a user, each defaulting to host user
  /// presence; host user presence when none requires one.
  static func assuranceFloor(forPlan plan: JSONValue?) throws(ShowcaseError) -> AssuranceTier {
    var floors: [AssuranceTier] = []
    let items = try ShowcaseJavaScript.arrayOrEmpty(
      ShowcaseJavaScript.optionalMember(plan, "selected_items"),
      calling: "map",
    )
    var policies: [JSONValue?] = []
    for item in items {
      try policies.append(ShowcaseJavaScript.member(item, "approval_policy_snapshot"))
    }
    for policy in policies {
      guard try requiresUserApproval(policy) else {
        continue
      }
      let declared = ShowcaseJavaScript.optionalMember(policy, "minimum_assurance_tier")
      floors
        .append(declared?.stringValue.flatMap(AssuranceTier.recognised) ?? .trustedHostUserPresence)
    }
    guard var floor = floors.first else {
      return .trustedHostUserPresence
    }
    for candidate in floors.dropFirst() where candidate.meets(floor) {
      floor = candidate
    }
    return floor
  }

  /// `policyRequiresUserApproval`: a predefined policy with an array of
  /// requirements, one of them an object whose approver is a user.
  private static func requiresUserApproval(_ policy: JSONValue?) throws(ShowcaseError) -> Bool {
    guard try ShowcaseJavaScript.isString(ShowcaseJavaScript.member(policy, "mode"), "predefined"),
          let requirements = ShowcaseJavaScript.optionalMember(policy, "requirements")?.arrayValue
    else {
      return false
    }
    return requirements.contains { requirement in
      ShowcaseJavaScript.isString(requirement.objectValue?["approver_type"], "user")
    }
  }

  /// The `planRequiresUserApproval` / `userApprovalRequired` check both
  /// appendShowcaseEvent.ts and replayRun.ts spell out: unlike the floor's
  /// check, a `null` requirement is read, and throws.
  static func requiresUserApproval(plan: JSONValue?) throws(ShowcaseError) -> Bool {
    let items = try ShowcaseJavaScript.arrayOrEmpty(
      ShowcaseJavaScript.optionalMember(plan, "selected_items"),
      calling: "some",
    )
    for item in items {
      let policy = try ShowcaseJavaScript.member(item, "approval_policy_snapshot")
      guard try ShowcaseJavaScript.isString(
        ShowcaseJavaScript.member(policy, "mode"),
        "predefined",
      ),
        let requirements = ShowcaseJavaScript.optionalMember(policy, "requirements")?.arrayValue
      else {
        continue
      }
      for requirement in requirements {
        let approver = try ShowcaseJavaScript.member(requirement, "approver_type")
        if ShowcaseJavaScript.isString(approver, "user") {
          return true
        }
      }
    }
    return false
  }
}
