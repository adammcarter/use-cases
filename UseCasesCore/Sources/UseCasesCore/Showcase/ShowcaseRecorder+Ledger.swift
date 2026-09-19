/// The shared append path, event construction and lookups
/// (packages/core/src/showcase/appendShowcaseEvent.ts).
extension ShowcaseRecorder {
  /// `appendEvent`.
  func appendEvent(
    _ runIdentifier: String,
    _ eventType: String,
    _ recording: ShowcaseRecording,
    _ payload: JSONObject,
  ) throws(ShowcaseError) -> JSONValue {
    let context = recording.context
    let read = try ShowcaseLedger.read(context: context, runIdentifier: runIdentifier)
    guard read.isComplete else {
      throw .ledgerDamaged
    }
    let existing = try Self.event(in: read.events, keyedBy: recording.idempotencyKey)
    let digest = Self.intentDigest(eventType, payload, recording)
    if let existing {
      guard try ShowcaseJavaScript.isString(
        ShowcaseJavaScript.member(existing, "intent_digest"),
        digest,
      ) else {
        throw .idempotencyConflict
      }
      return existing
    }
    let event = makeEvent(
      runIdentifier: runIdentifier,
      eventType: eventType,
      sequence: read.events.count + 1,
      payload: payload,
      recording: recording,
    )
    try ShowcaseLedger.appendLine(context: context, runIdentifier: runIdentifier, event: event)
    return event
  }

  /// `makeEvent`: `recorded_at` is the caller's, else the clock's instant.
  func makeEvent(
    runIdentifier: String,
    eventType: String,
    sequence: Int,
    payload: JSONObject,
    recording: ShowcaseRecording,
  ) -> JSONValue {
    let recordedAt = recording.recordedAt ?? JavaScriptTimestamp
      .isoString(milliseconds: clock.now())
    return .object(JSONObject([
      ("schema_version", .number(1)),
      ("event_type", .string(eventType)),
      ("event_id", .string("evt.\(runIdentifier).\(sequence)")),
      ("run_id", .string(runIdentifier)),
      ("aggregate_id", .string(runIdentifier)),
      ("sequence", .number(Double(sequence))),
      ("recorded_at", .string(recordedAt)),
      ("actor_type", .string(recording.actorType.rawValue)),
      ("host_surface", .string(recording.hostSurface)),
      ("idempotency_key", .string(recording.idempotencyKey)),
      ("intent_digest", .string(Self.intentDigest(eventType, payload, recording))),
      ("payload", .object(payload)),
    ]))
  }

  /// `appendResult`: the event, and the run replayed from a fresh read as if
  /// complete — whatever the read found.
  func appendResult(
    context: ResolvedWorkspaceContext,
    event: JSONValue,
    trust: ShowcaseTrustResolvers = .none,
  ) throws(ShowcaseError) -> ShowcaseAppendResult {
    let runIdentifier = event["run_id"]
    let read = try ShowcaseLedger.read(
      context: context,
      runIdentifier: JavaScriptString.text(of: runIdentifier),
    )
    let status = try ShowcaseReplay.replay(
      runIdentifier: runIdentifier,
      events: read.events,
      isLedgerComplete: true,
      trust: trust,
    )
    return ShowcaseAppendResult(event: event, status: status)
  }

  /// `runIdFrom`: `run.` and the first non-empty of the idempotency key, the
  /// caller's `recorded_at` and the clock's instant, sanitised.
  func runIdentifier(_ recording: ShowcaseRecording) -> String {
    let source = if !recording.idempotencyKey.isEmpty {
      recording.idempotencyKey
    } else if let recordedAt = recording.recordedAt, !recordedAt.isEmpty {
      recordedAt
    } else {
      JavaScriptTimestamp.isoString(milliseconds: clock.now())
    }
    return "run.\(Self.sanitized(source))"
  }

  /// `sanitizeId`: lowercased, every run of code units outside `[a-z0-9]`
  /// made one `_`, leading and trailing `_` removed, `showcase` if nothing is
  /// left.
  static func sanitized(_ value: String) -> String {
    var units: [UInt16] = []
    var isInRun = false
    for unit in value.lowercased().utf16 {
      let isKept = (0x61 ... 0x7A).contains(unit) || (0x30 ... 0x39).contains(unit)
      if isKept {
        units.append(unit)
        isInRun = false
      } else if !isInRun {
        units.append(CodeUnits.lowLine)
        isInRun = true
      }
    }
    while units.first == CodeUnits.lowLine {
      units.removeFirst()
    }
    while units.last == CodeUnits.lowLine {
      units.removeLast()
    }
    return units.isEmpty ? "showcase" : CodeUnits.string(units)
  }

  /// `intentDigestFor`: the semantic hash of the event type, payload, actor
  /// and host, under their camelCase names.
  static func intentDigest(
    _ eventType: String,
    _ payload: JSONObject,
    _ recording: ShowcaseRecording,
  ) -> String {
    SemanticHash.compute(.object(JSONObject([
      ("eventType", .string(eventType)),
      ("payload", .object(payload)),
      ("actorType", .string(recording.actorType.rawValue)),
      ("hostSurface", .string(recording.hostSurface)),
    ])))
  }

  /// `events.find((event) => event.idempotency_key === key)`.
  static func event(
    in events: [JSONValue],
    keyedBy idempotencyKey: String,
  ) throws(ShowcaseError) -> JSONValue? {
    try event(in: events, member: "idempotency_key", equals: idempotencyKey)
  }

  /// `events.find((event) => event.event_id === identifier)`.
  static func event(
    in events: [JSONValue],
    identifiedBy identifier: String,
  ) throws(ShowcaseError) -> JSONValue? {
    try event(in: events, member: "event_id", equals: identifier)
  }

  private static func event(
    in events: [JSONValue],
    member: String,
    equals text: String,
  ) throws(ShowcaseError) -> JSONValue? {
    for event in events {
      let value = try ShowcaseJavaScript.member(event, member)
      guard ShowcaseJavaScript.isString(value, text) else {
        continue
      }
      return event
    }
    return nil
  }
}
