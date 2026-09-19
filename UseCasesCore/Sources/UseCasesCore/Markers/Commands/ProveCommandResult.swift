/// The key a trusted prove signs with.
public struct ProveSigningKey: Sendable {
  /// An ed25519 PKCS#8 PEM private key.
  public let privateKeyPEM: String
  public let keyIdentifier: String

  public init(
    privateKeyPEM: String,
    keyIdentifier: String,
  ) {
    self.privateKeyPEM = privateKeyPEM
    self.keyIdentifier = keyIdentifier
  }
}

/// The GitHub-shaped producer block's caller-supplied members; each nil takes
/// its default.
public struct ProveProducer: Sendable {
  public var identifier: String?
  public var version: String?
  public var runIdentifier: String?
  public var repository: String?
  public var commit: String?

  public init(
    identifier: String? = nil,
    version: String? = nil,
    runIdentifier: String? = nil,
    repository: String? = nil,
    commit: String? = nil,
  ) {
    self.identifier = identifier
    self.version = version
    self.runIdentifier = runIdentifier
    self.repository = repository
    self.commit = commit
  }
}

/// A row's verdict: `signed` appended a proof; `candidate` would pass but was
/// not appended; `skipped_*` did no work; `failed` was refused.
public enum ProveRowStatus: String, Equatable, Sendable {
  case signed
  case candidate
  case skippedUnbound = "skipped_unbound"
  case skippedFresh = "skipped_fresh"
  case skippedVariantFamily = "skipped_variant_family"
  case failed
}

public struct ProveRowResult: Equatable, Sendable {
  public let rowIdentifier: String
  public let status: ProveRowStatus
  public let reason: String?
  public let message: String?
  public let proofEventAppended: Bool
  public let eventIdentifier: String?
  public let rowHash: String?
  public let bindingSetHash: String?

  init(
    _ rowIdentifier: String,
    _ status: ProveRowStatus,
    reason: String? = nil,
    message: String? = nil,
    proofEventAppended: Bool = false,
    eventIdentifier: String? = nil,
    hashes: (rowHash: String, bindingSetHash: String)? = nil,
  ) {
    self.rowIdentifier = rowIdentifier
    self.status = status
    self.reason = reason
    self.message = message
    self.proofEventAppended = proofEventAppended
    self.eventIdentifier = eventIdentifier
    rowHash = hashes?.rowHash
    bindingSetHash = hashes?.bindingSetHash
  }

  var jsonValue: JSONValue {
    let nullable = { (text: String?) in
      text.map(JSONValue.string) ?? .null
    }
    return .object(JSONObject([
      ("row_id", .string(rowIdentifier)),
      ("status", .string(status.rawValue)),
      ("reason", nullable(reason)),
      ("message", nullable(message)),
      ("proof_event_appended", .bool(proofEventAppended)),
      ("event_id", nullable(eventIdentifier)),
      ("row_hash", nullable(rowHash)),
      ("binding_set_hash", nullable(bindingSetHash)),
    ]))
  }
}

public struct ProveCommandResult: Equatable, Sendable {
  public let exitCode: Int
  public let isOK: Bool
  public let trusted: Bool
  public let rows: [ProveRowResult]
  public let proofEventsAppended: Int
  public let errors: [MarkerCommandFailure]

  init(
    exitCode: Int,
    trusted: Bool,
    rows: [ProveRowResult] = [],
    errors: [MarkerCommandFailure] = [],
  ) {
    self.exitCode = exitCode
    isOK = exitCode == 0
    self.trusted = trusted
    self.rows = rows
    proofEventsAppended = rows.count { row in
      row.proofEventAppended
    }
    self.errors = errors
  }

  /// The TypeScript's `commandResult({...})` spread, in its key order.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("command", .string("prove")),
      ("ok", .bool(isOK)),
      ("trusted", .bool(trusted)),
      ("rows", .array(rows.map(\.jsonValue))),
      ("proof_events_appended", .number(Double(proofEventsAppended))),
      ("errors", .array(errors.map(\.jsonValue))),
      ("exit_code", .number(Double(exitCode))),
    ]))
  }
}
