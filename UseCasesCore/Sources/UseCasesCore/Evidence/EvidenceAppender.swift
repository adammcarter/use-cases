/// What to record (`AppendEvidenceEventOptions`).
public struct EvidenceAppendOptions: Sendable {
  public let context: ResolvedWorkspaceContext
  public let idempotencyKey: String
  public let target: EvidenceTarget
  /// Unvalidated, as the TypeScript's callers pass it.
  public let kind: String
  /// Unvalidated, as the TypeScript's callers pass it.
  public let result: String
  public let summary: String
  public let actorType: EvidenceActorType
  public let hostSurface: String
  /// Supplied for a performed run; derived from ``actorType`` when nil.
  public let method: EvidenceObservationMethod?

  public init(
    context: ResolvedWorkspaceContext,
    idempotencyKey: String,
    target: EvidenceTarget,
    kind: String,
    result: String,
    summary: String,
    actorType: EvidenceActorType,
    hostSurface: String,
    method: EvidenceObservationMethod? = nil,
  ) {
    self.context = context
    self.idempotencyKey = idempotencyKey
    self.target = target
    self.kind = kind
    self.result = result
    self.summary = summary
    self.actorType = actorType
    self.hostSurface = hostSurface
    self.method = method
  }
}

/// What to void (`VoidEvidenceEventOptions`).
public struct EvidenceVoidOptions: Sendable {
  public let context: ResolvedWorkspaceContext
  public let evidenceIdentifier: String
  public let expectedHeadEventIdentifier: String
  public let reason: String
  public let idempotencyKey: String
  public let actorType: EvidenceActorType
  public let hostSurface: String

  public init(
    context: ResolvedWorkspaceContext,
    evidenceIdentifier: String,
    expectedHeadEventIdentifier: String,
    reason: String,
    idempotencyKey: String,
    actorType: EvidenceActorType,
    hostSurface: String,
  ) {
    self.context = context
    self.evidenceIdentifier = evidenceIdentifier
    self.expectedHeadEventIdentifier = expectedHeadEventIdentifier
    self.reason = reason
    self.idempotencyKey = idempotencyKey
    self.actorType = actorType
    self.hostSurface = hostSurface
  }
}

/// `AppendEvidenceEventResult`.
public struct EvidenceAppendResult: Sendable, Equatable {
  /// False when an identical intent was already recorded under the key.
  public let isAppended: Bool
  public let event: EvidenceEvent
  /// Relative to the data root.
  public let ledgerRelativePath: String
  /// Absolute.
  public let ledgerPath: String

  /// `toEvidenceAppendResult`: the `evidence-append-result` wire data.
  public func resultData() -> JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("appended", .bool(isAppended)),
      ("event", event.jsonValue),
      ("ledger_path", .string(ledgerRelativePath)),
      ("durability", .string("file_synced")),
    ]))
  }
}

/// Appends evidence events under the cross-process append lock
/// (packages/core/src/evidence/appendEvidenceEvent.ts).
///
/// The lock is a directory: `mkdir <evidence root>/.locks/append.lock`
/// succeeds for exactly one caller across every process, and the others poll
/// every 25ms until a 30-second deadline, then give up. It is removed when the
/// work is done, whether the work succeeded or threw. There is no stale-lock
/// recovery: a lock left by a crashed process stays until someone removes it.
///
/// Nothing in this process serialises appends — no actor or in-memory lock
/// stands in front of the directory — so two appends in one process contend
/// for it exactly as two processes do. The wait between attempts is an
/// `await` on the injected ``EvidenceClock``, which suspends the Task instead
/// of blocking a thread of Swift's cooperative pool; the work under the lock
/// is a handful of short synchronous filesystem calls, as everywhere else in
/// this package.
public struct EvidenceAppender: Sendable {
  let clock: any EvidenceClock
  let randomSource: any EvidenceRandomSource

  public init(
    clock: any EvidenceClock = SystemEvidenceClock(),
    randomSource: any EvidenceRandomSource = SystemEvidenceRandomSource(),
  ) {
    self.clock = clock
    self.randomSource = randomSource
  }

  /// `appendEvidenceEvent`. The summary is redacted before anything else sees
  /// it, so the stored summary and its intent digest agree and the durable
  /// ledger never holds the secret.
  public func append(_ options: EvidenceAppendOptions) async throws(EvidenceEventError)
    -> EvidenceAppendResult
  {
    let redacted = EvidenceAppendOptions(
      context: options.context,
      idempotencyKey: options.idempotencyKey,
      target: options.target,
      kind: options.kind,
      result: options.result,
      summary: Redactor.redactSecrets(options.summary),
      actorType: options.actorType,
      hostSurface: options.hostSurface,
      method: options.method,
    )
    return try await withAppendLock(context: redacted
      .context)
    { () async throws(EvidenceEventError) in
      try await appendUnderLock(redacted)
    }
  }

  /// `appendEvidenceVoidEvent`. The reason is not redacted.
  public func appendVoid(_ options: EvidenceVoidOptions) async throws(EvidenceEventError)
    -> EvidenceAppendResult
  {
    try await withAppendLock(context: options.context) { () async throws(EvidenceEventError) in
      try await voidUnderLock(options)
    }
  }

  private func appendUnderLock(_ options: EvidenceAppendOptions) async throws(EvidenceEventError)
    -> EvidenceAppendResult
  {
    let snapshot = try EvidenceReplay.replay(context: options.context)
    guard snapshot.isComplete else {
      throw .ledgerDamaged
    }
    let digest = try Self.intentDigest(for: options)
    if let existing = try Self.existingResult(
      for: options.idempotencyKey,
      digest: digest,
      snapshot,
      options.context,
    ) {
      return existing
    }

    let stamp = await stamped()
    let event = EvidenceEventRecord.recorded(
      options,
      eventIdentifier: stamp.eventIdentifier,
      intentDigest: digest,
      recordedAt: stamp.recordedAt,
    )
    let ledgerPath = Self.ledgerPath(options.context, evidenceIdentifier: stamp.eventIdentifier)
    do throws(FileAccessError) {
      try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(ledgerPath))
    } catch {
      throw .fileAccess(error)
    }
    return try Self.written(event, to: ledgerPath, context: options.context)
  }

  private func voidUnderLock(_ options: EvidenceVoidOptions) async throws(EvidenceEventError)
    -> EvidenceAppendResult
  {
    let snapshot = try EvidenceReplay.replay(context: options.context)
    guard snapshot.isComplete else {
      throw .ledgerDamaged
    }
    let aggregate = try Self.voidableAggregate(in: snapshot, options)
    let digest = try Self.intentDigest(for: options)
    if let existing = try Self.existingResult(
      for: options.idempotencyKey,
      digest: digest,
      snapshot,
      options.context,
    ) {
      return existing
    }

    let stamp = await stamped()
    let event = EvidenceEventRecord.voided(
      options,
      eventIdentifier: stamp.eventIdentifier,
      sequence: aggregate.eventIdentifiers.count + 1,
      intentDigest: digest,
      recordedAt: stamp.recordedAt,
    )
    // Unlike a record, a void does not create the ledger's directory first.
    let ledgerPath = Self.ledgerPath(
      options.context,
      evidenceIdentifier: options.evidenceIdentifier,
    )
    return try Self.written(event, to: ledgerPath, context: options.context)
  }

  /// The event id (`uuidv7()`: `Date.now()`, then the random bytes), then the
  /// `new Date()` for `recorded_at` — the clock read twice, in that order.
  private func stamped() async -> (eventIdentifier: String, recordedAt: String) {
    let milliseconds = await clock.now()
    let eventIdentifier = EvidenceEventIdentifier.make(
      milliseconds: milliseconds,
      randomBytes: randomSource.bytes(count: 10),
    )
    let recordedAt = await JavaScriptTimestamp.isoString(milliseconds: clock.now())
    return (eventIdentifier, recordedAt)
  }

  /// The aggregate to void: present, active, and at the caller's expected head.
  private static func voidableAggregate(
    in snapshot: EvidenceSnapshot,
    _ options: EvidenceVoidOptions,
  ) throws(EvidenceEventError) -> EvidenceAggregateState {
    let aggregate = snapshot.aggregates.first { aggregate in
      JavaScriptString.identical(aggregate.evidenceIdentifier, options.evidenceIdentifier)
    }
    guard let aggregate, aggregate.status == .active else {
      throw .invalidTransition
    }
    guard let head = aggregate.eventIdentifiers.last,
          JavaScriptString.identical(head, options.expectedHeadEventIdentifier)
    else {
      throw .expectedHeadMismatch
    }
    return aggregate
  }

  /// An earlier event under the same idempotency key: the same intent returns
  /// it unappended, a different intent is a conflict.
  private static func existingResult(
    for idempotencyKey: String,
    digest: String,
    _ snapshot: EvidenceSnapshot,
    _ context: ResolvedWorkspaceContext,
  ) throws(EvidenceEventError) -> EvidenceAppendResult? {
    let existing = snapshot.events.first { event in
      JavaScriptValue.strictlyEquals(event["idempotency_key"], idempotencyKey)
    }
    guard let existing else {
      return nil
    }
    guard JavaScriptValue.strictlyEquals(existing["intent_digest"], digest) else {
      throw .idempotencyConflict
    }
    let path = ledgerPath(context, evidenceIdentifier: existing.aggregateIdentifier)
    return EvidenceAppendResult(
      isAppended: false,
      event: existing,
      ledgerRelativePath: EvidenceLedgerReader.relativePath(context: context, path: path),
      ledgerPath: path,
    )
  }

  /// `digestIntent` for a record.
  private static func intentDigest(for options: EvidenceAppendOptions) throws(EvidenceEventError)
    -> String
  {
    try digest(of: JSONObject([
      ("target", options.target.jsonValue),
      ("kind", .string(options.kind)),
      ("result", .string(options.result)),
      ("summary", .string(options.summary)),
      ("actorType", .string(options.actorType.rawValue)),
      ("hostSurface", .string(options.hostSurface)),
    ]))
  }

  /// `digestIntent` for a void: the evidence id as the target, under the zero
  /// hash, recorded as an observed manual observation whose summary is the
  /// reason.
  private static func intentDigest(for options: EvidenceVoidOptions) throws(EvidenceEventError)
    -> String
  {
    let target = EvidenceTarget(
      useCaseIdentifier: options.evidenceIdentifier,
      scenarioIdentifier: nil,
      useCaseSemanticHash: EvidenceAggregateProjection.zeroHash,
    )
    return try digest(of: JSONObject([
      ("target", target.jsonValue),
      ("kind", .string("manual_observation")),
      ("result", .string("observed")),
      ("summary", .string(options.reason)),
      ("actorType", .string(options.actorType.rawValue)),
      ("hostSurface", .string(options.hostSurface)),
    ]))
  }

  /// sha256 over canonical JSON of the six camelCase intent members — sorted
  /// keys, unlike the event line itself.
  private static func digest(of intent: JSONObject) throws(EvidenceEventError) -> String {
    do throws(CodeUnitCanonicalJSONError) {
      return try CodeUnitCanonicalJSON.sha256(.object(intent))
    } catch {
      throw .nonFiniteNumber
    }
  }

  /// `<evidence root>/by-id/<first two UTF-16 code units>/<id>.jsonl`.
  static func ledgerPath(
    _ context: ResolvedWorkspaceContext,
    evidenceIdentifier: String,
  ) -> String {
    let prefix = CodeUnits.string(evidenceIdentifier.utf16.prefix(2))
    return NodePath.join(
      EvidenceLedgerReader.evidenceRoot(context: context),
      "by-id",
      prefix,
      "\(evidenceIdentifier).jsonl",
    )
  }

  /// Open for append, one `write` of `JSON.stringify(event) + "\n"`, a
  /// best-effort sync, close.
  private static func written(
    _ event: EvidenceEvent,
    to path: String,
    context: ResolvedWorkspaceContext,
  ) throws(EvidenceEventError) -> EvidenceAppendResult {
    do throws(FileAccessError) {
      try LedgerAppend.appendLine(JSONWriter.encode(event.jsonValue) + "\n", toPath: path)
    } catch {
      throw .fileAccess(error)
    }
    return EvidenceAppendResult(
      isAppended: true,
      event: event,
      ledgerRelativePath: EvidenceLedgerReader.relativePath(context: context, path: path),
      ledgerPath: path,
    )
  }
}
