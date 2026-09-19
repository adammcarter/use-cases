import Foundation

/// The clock the showcase code reads: `Date.now()` for a token's expiry check
/// and a minted request's issue time, and `new Date()` for a `recorded_at` or
/// run id the caller did not supply. Synchronous, as every showcase call is.
public protocol ShowcaseClock: Sendable {
  /// Milliseconds since the epoch, whole, as `Date.now()` answers.
  func now() -> Double
}

/// The source of `crypto.randomUUID()`, which names an approval request's nonce.
public protocol ShowcaseUUIDSource: Sendable {
  /// A version 4 UUID in lowercase, as node spells one.
  func randomUUID() -> String
}

/// The process's own clock.
public struct SystemShowcaseClock: ShowcaseClock {
  /// Reads the system time.
  public init() {}

  public func now() -> Double {
    (Date().timeIntervalSince1970 * 1000).rounded(.down)
  }
}

/// The system's generator.
public struct SystemShowcaseUUIDSource: ShowcaseUUIDSource {
  /// Draws from the system generator.
  public init() {}

  public func randomUUID() -> String {
    UUID().uuidString.lowercased()
  }
}

/// Who recorded an event.
///
/// `other` carries a value the CLI passed through unchecked: `showcase
/// record-verdict --actor robot` reaches the ledger as `robot` in the
/// TypeScript, which never validates the flag, so the port must be able to
/// record it too. Only `user` is ever compared, and an `other` actor is not
/// one.
public enum ShowcaseActorType: RawRepresentable, Equatable, Sendable {
  case user
  case agent
  case script
  case system
  case other(String)

  public init(rawValue: String) {
    switch rawValue {
    case "user": self = .user
    case "agent": self = .agent
    case "script": self = .script
    case "system": self = .system
    default: self = .other(rawValue)
    }
  }

  public var rawValue: String {
    switch self {
    case .user: "user"
    case .agent: "agent"
    case .script: "script"
    case .system: "system"
    case let .other(value): value
    }
  }
}

/// Who leads the run.
public enum ShowcaseControlMode: String, CaseIterable, Sendable {
  case agentLed = "agent_led"
  case userLed = "user_led"
  case scriptLed = "script_led"
  case mixed
}

/// A verdict on one plan item.
///
/// `other` carries a value the CLI passed through unchecked, as
/// ``ShowcaseActorType/other(_:)`` does: `--verdict maybe` is recorded as
/// `maybe` in the TypeScript and replays as neither a pass nor a failure.
public enum ShowcaseVerdict: RawRepresentable, Equatable, Sendable {
  case pass
  case partial
  case fail
  case waived
  case blocked
  case other(String)

  public init(rawValue: String) {
    switch rawValue {
    case "pass": self = .pass
    case "partial": self = .partial
    case "fail": self = .fail
    case "waived": self = .waived
    case "blocked": self = .blocked
    default: self = .other(rawValue)
    }
  }

  public var rawValue: String {
    switch self {
    case .pass: "pass"
    case .partial: "partial"
    case .fail: "fail"
    case .waived: "waived"
    case .blocked: "blocked"
    case let .other(value): value
    }
  }
}

/// What to do about a failed or blocked verdict.
///
/// `other` carries a value the CLI passed through unchecked, as
/// ``ShowcaseVerdict/other(_:)`` does: `--decision waive` is recorded as
/// `waive`, which is not one of the four the replay acts on.
public enum ShowcaseFailureDecision: RawRepresentable, Equatable, Sendable {
  case `continue`
  case pauseToFix
  case waiveWithReason
  case abort
  case other(String)

  public init(rawValue: String) {
    switch rawValue {
    case "continue": self = .continue
    case "pause_to_fix": self = .pauseToFix
    case "waive_with_reason": self = .waiveWithReason
    case "abort": self = .abort
    default: self = .other(rawValue)
    }
  }

  public var rawValue: String {
    switch self {
    case .continue: "continue"
    case .pauseToFix: "pause_to_fix"
    case .waiveWithReason: "waive_with_reason"
    case .abort: "abort"
    case let .other(value): value
    }
  }
}

/// Why an epoch started.
public enum ShowcaseEpochReason: String, CaseIterable, Sendable {
  case workspaceChanged = "workspace_changed"
}

/// What an approval records.
public enum ShowcaseApprovalDecision: String, CaseIterable, Sendable {
  case approved
  case approvedWithKnownGaps = "approved_with_known_gaps"
}

/// The known gaps a partial plan's run was started in acknowledgement of:
/// `{ acknowledged: true, gaps }`.
public struct ShowcaseKnownGapAcknowledgement: Equatable, Sendable {
  public let gaps: [String]

  public init(gaps: [String]) {
    self.gaps = gaps
  }

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("acknowledged", .bool(true)),
      ("gaps", .array(gaps.map(JSONValue.string))),
    ]))
  }
}

/// What every recorded event carries besides its payload: the workspace, the
/// actor and host, the idempotency key, and an optional `recorded_at` (the
/// clock's instant when nil).
public struct ShowcaseRecording: Sendable {
  public let context: ResolvedWorkspaceContext
  public let actorType: ShowcaseActorType
  public let hostSurface: String
  public let idempotencyKey: String
  public let recordedAt: String?

  public init(
    context: ResolvedWorkspaceContext,
    actorType: ShowcaseActorType,
    hostSurface: String,
    idempotencyKey: String,
    recordedAt: String? = nil,
  ) {
    self.context = context
    self.actorType = actorType
    self.hostSurface = hostSurface
    self.idempotencyKey = idempotencyKey
    self.recordedAt = recordedAt
  }
}

/// The resolvers a caller's keyring supplies so approval trust is computed
/// from the signed token (`ApprovalVerificationOptions` and
/// `ReplayTrustOptions`).
public struct ShowcaseTrustResolvers: Sendable {
  public let publicKeyResolver: PublicKeyResolver?
  public let tierResolver: (@Sendable (String, String?) -> KeyringAssuranceTier?)?
  public let webAuthnCredentialResolver: (@Sendable (String, String?) -> WebAuthnCredential?)?

  public init(
    publicKeyResolver: PublicKeyResolver? = nil,
    tierResolver: (@Sendable (String, String?) -> KeyringAssuranceTier?)? = nil,
    webAuthnCredentialResolver: (@Sendable (String, String?) -> WebAuthnCredential?)? = nil,
  ) {
    self.publicKeyResolver = publicKeyResolver
    self.tierResolver = tierResolver
    self.webAuthnCredentialResolver = webAuthnCredentialResolver
  }

  /// No resolver at all: every user decision is untrusted.
  public static let none = ShowcaseTrustResolvers()

  /// All three resolvers over one keyring.
  public init(keyring: Keyring) {
    self.init(
      publicKeyResolver: keyring.publicKeyResolver(),
      tierResolver: keyring.maxAssuranceTierResolver(),
      webAuthnCredentialResolver: keyring.webAuthnCredentialResolver(),
    )
  }
}

/// `ShowcaseAppendResult`: the event recorded (or found under its idempotency
/// key) and the run's status after it.
public struct ShowcaseAppendResult: Sendable {
  public let event: JSONValue
  public let status: ShowcaseRunStatus

  public var jsonValue: JSONValue {
    let eventIdentifier = event.objectValue?["event_id"]
    var result = JSONObject()
    result["schema_version"] = .number(1)
    result["run_id"] = event.objectValue?["run_id"]
    result["appended_event_ids"] = .array([eventIdentifier ?? .null])
    result["event"] = event
    result["status"] = status.jsonValue
    return .object(result)
  }
}
