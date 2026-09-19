/// The two events the append path builds, members in the order the
/// TypeScript object literals declare them — which is the order
/// `JSON.stringify` writes them to the ledger.
enum EvidenceEventRecord {
  /// `recordedEventFromOptions`. `captured_at` is the same instant as
  /// `recorded_at`: one `new Date()`.
  static func recorded(
    _ options: EvidenceAppendOptions,
    eventIdentifier: String,
    intentDigest: String,
    recordedAt: String,
  ) -> EvidenceEvent {
    let defaultMethod = EvidenceObservationMethod(
      type: options.actorType == .script ? .structuredCommand : .reported,
    )
    let verifier = options.actorType == .system ? EvidenceActorType.agent : options.actorType
    let verdict = options.result == "inconclusive" || options.result == "observed"
      ? "partial"
      : options.result
    let payload = JSONObject([
      ("targets", .array([options.target.jsonValue])),
      ("kind", .string(options.kind)),
      ("captured_at", .string(recordedAt)),
      ("result", .string(options.result)),
      ("summary", .string(options.summary)),
      ("producer", .object(JSONObject([("type", .string(options.actorType.rawValue))]))),
      ("method", (options.method ?? defaultMethod).jsonValue),
      ("evidence_kind", .string(options.kind)),
      ("use_case_ids", .array([.string(options.target.useCaseIdentifier)])),
      ("verifier", .object(JSONObject([("type", .string(verifier.rawValue))]))),
      ("verdict", .string(verdict)),
    ])
    let object = JSONObject([
      ("schema_version", .number(1)),
      ("event_type", .string("evidence_recorded")),
      ("event_id", .string(eventIdentifier)),
      ("aggregate_id", .string(eventIdentifier)),
      ("sequence", .number(1)),
      ("recorded_at", .string(recordedAt)),
      ("actor_type", .string(options.actorType.rawValue)),
      ("host_surface", .string(options.hostSurface)),
      ("idempotency_key", .string(options.idempotencyKey)),
      ("intent_digest", .string(intentDigest)),
      ("payload", .object(payload)),
    ])
    return EvidenceEvent(
      object: object,
      eventType: "evidence_recorded",
      eventIdentifier: eventIdentifier,
      aggregateIdentifier: eventIdentifier,
      sequence: 1,
    )
  }

  /// The `evidence_voided` event `voidUnderLock` builds.
  static func voided(
    _ options: EvidenceVoidOptions,
    eventIdentifier: String,
    sequence: Int,
    intentDigest: String,
    recordedAt: String,
  ) -> EvidenceEvent {
    let object = JSONObject([
      ("schema_version", .number(1)),
      ("event_type", .string("evidence_voided")),
      ("event_id", .string(eventIdentifier)),
      ("aggregate_id", .string(options.evidenceIdentifier)),
      ("sequence", .number(Double(sequence))),
      ("recorded_at", .string(recordedAt)),
      ("actor_type", .string(options.actorType.rawValue)),
      ("host_surface", .string(options.hostSurface)),
      ("idempotency_key", .string(options.idempotencyKey)),
      ("intent_digest", .string(intentDigest)),
      ("target_event_id", .string(options.expectedHeadEventIdentifier)),
      ("reason", .string(options.reason)),
    ])
    return EvidenceEvent(
      object: object,
      eventType: "evidence_voided",
      eventIdentifier: eventIdentifier,
      aggregateIdentifier: options.evidenceIdentifier,
      sequence: Double(sequence),
    )
  }
}
