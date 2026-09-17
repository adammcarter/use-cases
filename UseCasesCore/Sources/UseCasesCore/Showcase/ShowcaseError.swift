/// Why a showcase run could not be started, recorded, replayed or approved.
///
/// The port of every `UseCasesPluginError` packages/core/src/showcase throws,
/// plus the errors it lets escape: node's filesystem errors, the TypeErrors V8
/// raises reading members of foreign ledger lines, and the two plain `Error`s
/// with no code. Those last carry a code this port names, as
/// ``EvidenceEventError`` does for its own uncoded errors.
public enum ShowcaseError: Error, Equatable, Sendable {
  /// A partial-integrity plan was started without acknowledging its gaps.
  case knownGapAcknowledgementRequired
  /// An append met a ledger that did not read back complete.
  case ledgerDamaged
  /// A start met a ledger file that did not read back complete.
  case startAgainstDamagedLedger
  /// An idempotency key was reused for a different intent.
  case idempotencyConflict
  /// A different idempotency key sanitised to a run id that already has events.
  case runIdentifierConflict
  /// None of the named observations is an observation of the item.
  case verdictRequiresObservation
  /// The failure decision's target is missing or not a verdict.
  case failureDecisionTargetNotVerdict
  /// The failure decision's target verdict is not `fail` or `blocked`.
  case failureDecisionTargetNotFailure
  /// A failed or blocked verdict still has no failure decision.
  case failureDecisionRequired
  /// A non-user actor tried to record a decision on a user-approval plan.
  case userRequiredApproval
  /// An approval or rejection was recorded before any `run_finished`.
  case finishRequiredForApproval
  /// An approval binding was computed before any `run_finished`.
  case bindingRequiresFinish
  /// A user decision on a user-approval plan carried no signed token.
  case trustedUserConfirmationRequired
  /// The signed token failed verification.
  case approvalTokenRejected(failure: ApprovalTokenFailureCode, detail: String)
  /// A verified token's decision does not match the event being recorded.
  case approvalDecisionMismatch(detail: String)
  /// The correction's target is missing or not a `verdict_recorded` event.
  case invalidCorrectionTarget
  /// The plan's content hash is the all-zero placeholder.
  case planPlaceholderHash
  /// The plan's content hash does not match its body.
  case planHashMismatch
  /// A plan file could not be read or parsed; `detail` is the cause's message.
  case planFileUnreadable(detail: String)
  /// A plan file parsed but is not a version 1 plan with a string hash.
  case planFileInvalid
  /// An ed25519 approval token was asked to claim WebAuthn assurance.
  case webAuthnAssuranceOnEd25519Token
  /// The ed25519 signing key is not a PKCS#8 PEM.
  case invalidPrivateKey
  /// Canonical JSON met an absent value inside an array.
  case unsupportedCanonicalValue
  /// A request's issue or expiry time is outside JavaScript's date range.
  case invalidTimeValue
  /// A TypeError V8 raises on a foreign ledger line; `message` is V8's.
  case unreadableEvent(message: String)
  /// A filesystem call failed; node's error escapes in the TypeScript.
  case fileAccess(FileAccessError)

  public var code: String {
    switch self {
    case .knownGapAcknowledgementRequired: "showcase_known_gap_ack_required"
    case .ledgerDamaged, .startAgainstDamagedLedger: "showcase_ledger_damaged"
    case .idempotencyConflict: "showcase_idempotency_conflict"
    case .runIdentifierConflict: "showcase_run_id_conflict"
    case .verdictRequiresObservation: "showcase_verdict_requires_observation"
    case .failureDecisionTargetNotVerdict, .failureDecisionTargetNotFailure:
      "showcase_invalid_failure_decision_target"
    case .failureDecisionRequired: "showcase_failure_decision_required"
    case .userRequiredApproval: "showcase.user_required_approval"
    case .finishRequiredForApproval, .bindingRequiresFinish: "showcase.finish_required_for_approval"
    case .trustedUserConfirmationRequired: "showcase.trusted_user_confirmation_required"
    case let .approvalTokenRejected(failure, _): Self.pluginCode(for: failure)
    case .approvalDecisionMismatch: "showcase.approval_decision_mismatch"
    case .invalidCorrectionTarget: "showcase_invalid_correction_target"
    case .planPlaceholderHash: "showcase_plan_placeholder_hash"
    case .planHashMismatch: "showcase_plan_hash_mismatch"
    case .planFileUnreadable: "showcase_plan_file_unreadable"
    case .planFileInvalid: "showcase_plan_file_invalid"
    case .webAuthnAssuranceOnEd25519Token: "ed25519_webauthn_assurance_claim"
    case .invalidPrivateKey: ProofSignatureError.invalidPrivateKey.code
    case .unsupportedCanonicalValue: "unsupported_canonical_value"
    case .invalidTimeValue: "invalid_time_value"
    case .unreadableEvent: ProofSignatureError.unreadableEvent.code
    case let .fileAccess(error): error.code
    }
  }

  public var message: String {
    switch self {
    case .knownGapAcknowledgementRequired: "Partial plan requires known-gap acknowledgement."
    case .ledgerDamaged: "Refusing to append to damaged showcase history."
    case .startAgainstDamagedLedger: "Refusing to start against damaged showcase history."
    case .idempotencyConflict: "Idempotency key was reused with different intent."
    case .runIdentifierConflict: "Showcase run id already exists."
    case .verdictRequiresObservation: "Verdict requires a prior observation."
    case .failureDecisionTargetNotVerdict: "Failure decision target must be a verdict event."
    case .failureDecisionTargetNotFailure:
      "Failure decision target must be a failed or blocked verdict."
    case .failureDecisionRequired:
      "Cannot finish until each failed or blocked verdict has a failure decision."
    case .userRequiredApproval: "Agent cannot record user-required approval."
    case .finishRequiredForApproval: "User approval requires a finished showcase run."
    case .bindingRequiresFinish: "Approval binding requires a finished showcase run."
    case .trustedUserConfirmationRequired:
      "User approval requires a signed host approval token (out-of-band human sign-off)."
    case let .approvalTokenRejected(failure, detail):
      "User approval token rejected: \(failure.rawValue) (\(detail))"
    case let .approvalDecisionMismatch(detail):
      "User approval token rejected: DECISION_MISMATCH (\(detail))"
    case .invalidCorrectionTarget: "Correction target must be a verdict event."
    case .planPlaceholderHash: "Plan content hash must not be a placeholder."
    case .planHashMismatch: "Plan content hash does not match plan body."
    case let .planFileUnreadable(detail): "Presentation plan file could not be read: \(detail)"
    case .planFileInvalid: "Presentation plan file is not a v1 plan."
    case .webAuthnAssuranceOnEd25519Token:
      "ed25519 approval tokens cannot claim webauthn assurance"
    case .invalidPrivateKey: ProofSignatureError.invalidPrivateKey.message
    case .unsupportedCanonicalValue: "canonical_json: unsupported value type: undefined"
    case .invalidTimeValue: "Invalid time value"
    case let .unreadableEvent(message): message
    case let .fileAccess(error): error.message
    }
  }

  /// `approvalFailureCode`: the plugin code a token failure is reported under.
  static func pluginCode(for failure: ApprovalTokenFailureCode) -> String {
    switch failure {
    case .nonceBurned: "showcase.approval_nonce_burned"
    case .tokenExpired: "showcase.approval_token_expired"
    case .bindingMismatch: "showcase.approval_binding_mismatch"
    case .assuranceTooLow: "showcase.approval_assurance_too_low"
    case .assuranceOverClaim: "showcase.approval_assurance_over_claim"
    default: "showcase.trusted_user_confirmation_required"
    }
  }
}
