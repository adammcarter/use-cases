import Foundation

/// Why reading, replaying or appending evidence stopped.
///
/// The port of every `UseCasesPluginError` the evidence code throws, plus the
/// errors it lets escape: the TypeScript's `UseCasesPluginError(message, code)`
/// class is not ported as such — each domain has its own typed enum with a
/// `code` and `message`, and these five codes map to `UCM_EVIDENCE_*` public
/// codes through ``PublicErrorCodeMap``.
public enum EvidenceEventError: Error, Equatable, Sendable {
  /// The history holds damage, so nothing more may be appended to it.
  case ledgerDamaged
  /// An idempotency key was reused for a different intent.
  case idempotencyConflict
  /// The evidence to void is missing or no longer active.
  case invalidTransition
  /// The caller's expected head is not the aggregate's current head.
  case expectedHeadMismatch
  /// The append lock could not be taken — held past the deadline, or `mkdir`
  /// failing for any other reason, as the TypeScript reports both.
  case lockTimeout
  /// A filesystem call failed; node's error escapes in the TypeScript.
  case fileAccess(FileAccessError)
  /// A ledger is not valid UTF-8: node's `TextDecoder` throws, uncaught.
  case invalidEncoding
  /// A shape-valid event the TypeScript crashes on with a `TypeError`. The
  /// message is V8's; the TypeScript error has no code, and this one carries
  /// the code ``ProofSignatureError/unreadableEvent`` already uses.
  case unreadableEvent(message: String)
  /// Canonical JSON refused a non-finite number while comparing duplicates.
  case nonFiniteNumber

  public var code: String {
    switch self {
    case .ledgerDamaged: "evidence_ledger_damaged"
    case .idempotencyConflict: "evidence_idempotency_conflict"
    case .invalidTransition: "evidence_invalid_transition"
    case .expectedHeadMismatch: "evidence_expected_head_mismatch"
    case .lockTimeout: "evidence_lock_timeout"
    case let .fileAccess(error): error.code
    case .invalidEncoding: "ERR_ENCODING_INVALID_ENCODED_DATA"
    case .unreadableEvent: "unreadable_event"
    case .nonFiniteNumber: "non_finite_number"
    }
  }

  public var message: String {
    switch self {
    case .ledgerDamaged: "Refusing to append to damaged evidence history."
    case .idempotencyConflict: "Idempotency key was reused with different intent."
    case .invalidTransition: "Evidence aggregate is not active."
    case .expectedHeadMismatch: "Expected head event does not match current head."
    case .lockTimeout: "Timed out acquiring evidence append lock."
    case let .fileAccess(error): error.message
    case .invalidEncoding: UseCaseFileValidator.invalidEncodingMessage
    case let .unreadableEvent(message): message
    case .nonFiniteNumber: CodeUnitCanonicalJSONError.nonFiniteNumber.message
    }
  }
}
