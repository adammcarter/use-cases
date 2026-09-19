/// `projectAggregate` and `normalizeObservation` in replayEvidence.ts: one
/// aggregate's events folded into its current state.
struct EvidenceAggregateProjection {
  static let zeroHash = "sha256:0000000000000000000000000000000000000000000000000000000000000000"

  let aggregateIdentifier: String
  let events: [EvidenceEvent]
  let isInvalid: Bool
  private(set) var diagnostics: [Diagnostic] = []

  mutating func project() throws(EvidenceEventError) -> EvidenceAggregateState {
    guard !isInvalid, let ordered = validatedOrder() else {
      return invalid()
    }

    var head = ordered[0]
    var observation = try Self.normalizedObservation(head)
    var status = EvidenceAggregateStatus.active
    var replacement: JSONValue?

    for event in ordered.dropFirst() {
      guard JavaScriptValue.strictlyEquals(event["target_event_id"], head.eventIdentifier) else {
        return rejected(
          "evidence_invalid_transition",
          "Event must target the current aggregate head.",
        )
      }
      switch event.eventType {
      case "evidence_corrected" where Self.isExactly(event.eventType, "evidence_corrected"):
        guard JavaScriptValue.isTruthy(event["replacement"]), event.sequence > head.sequence else {
          return rejected(
            "evidence_invalid_transition",
            "Correction must contain a replacement and target an earlier head.",
          )
        }
        observation = try Self.normalizedObservation(event)
        head = event
        continue
      case "evidence_voided" where Self.isExactly(event.eventType, "evidence_voided"):
        status = .voided
      case "evidence_invalidated" where Self.isExactly(event.eventType, "evidence_invalidated"):
        status = .invalidated
      case "evidence_superseded" where Self.isExactly(event.eventType, "evidence_superseded"):
        if JavaScriptValue.strictlyEquals(event["replacement_evidence_id"], aggregateIdentifier) {
          return rejected("evidence_supersession_cycle", "Evidence cannot supersede itself.")
        }
        status = .superseded
        replacement = event["replacement_evidence_id"]
      default:
        continue
      }
      head = event
      break
    }

    return try state(observation: observation, status: status, replacement: replacement)
  }

  /// The events in sequence order, or nil once a diagnostic says why not.
  private mutating func validatedOrder() -> [EvidenceEvent]? {
    var perSequence: [Double: Int] = [:]
    for event in events {
      perSequence[event.sequence, default: 0] += 1
    }
    if perSequence.values.contains(where: { $0 > 1 }) {
      report("evidence_sequence_conflict", "Duplicate aggregate sequence.")
      return nil
    }
    let ordered = events.sorted { $0.sequence < $1.sequence }
    for (index, event) in ordered.enumerated() where event.sequence != Double(index + 1) {
      report("evidence_sequence_gap", "Aggregate sequence must start at 1 and be contiguous.")
      return nil
    }
    let recordedCount = ordered.count { event in
      Self.isExactly(event.eventType, "evidence_recorded")
    }
    guard recordedCount == 1, let first = ordered.first,
          Self.isExactly(first.eventType, "evidence_recorded")
    else {
      report(
        "evidence_invalid_transition",
        "Aggregate must contain exactly one initial evidence_recorded event.",
      )
      return nil
    }
    return ordered
  }

  private func state(
    observation: JSONObject?,
    status: EvidenceAggregateStatus,
    replacement: JSONValue?,
  ) throws(EvidenceEventError) -> EvidenceAggregateState {
    let targets = observation?["targets"]
    let targetLinks: [JSONValue]
    if let targets {
      // `(observation?.targets ?? []).map(...)`: anything but an array is a
      // TypeError, raised only once the freshness inputs map over it.
      guard let array = targets.arrayValue else {
        throw .unreadableEvent(message: "((intermediate value) ?? []).map is not a function")
      }
      targetLinks = array
    } else {
      targetLinks = []
    }
    let assurance = observation.map(Self.assurance) ?? JSONObject()

    var freshness = JSONObject()
    freshness["captured_at"] = observation?["captured_at"]
    var hashes: [JSONValue] = []
    for target in targetLinks {
      if target == .null {
        throw .unreadableEvent(
          message: "Cannot read properties of null (reading 'use_case_semantic_hash')",
        )
      }
      hashes.append(JavaScriptValue.member(target, "use_case_semantic_hash") ?? .null)
    }
    freshness["use_case_semantic_hashes"] = .array(hashes)
    freshness["explicit_invalidation"] = .bool(status == .invalidated)

    return EvidenceAggregateState(
      evidenceIdentifier: aggregateIdentifier,
      status: status,
      effectiveObservation: observation,
      targetLinks: targetLinks,
      assurance: assurance,
      freshnessInputs: freshness,
      eventIdentifiers: events.map(\.eventIdentifier),
      replacementEvidenceIdentifier: replacement,
    )
  }

  private static func assurance(_ observation: JSONObject) -> JSONObject {
    let kind = observation["kind"] ?? .null
    let methodType = JavaScriptValue.member(observation["method"], "type")
    let captureMethod: JSONValue? = JavaScriptValue.strictlyEquals(methodType, "structured_command")
      ? .string("executed")
      : methodType
    let executionMethod = JavaScriptValue.strictlyEquals(kind, "test_result")
      ? "test"
      : JavaScriptValue.strictlyEquals(kind, "command_result") ? "command" : "none"
    return EvidenceAssurance.derive(EvidenceAssuranceInput(
      kind: kind,
      origin: JavaScriptValue.member(observation["producer"], "type"),
      captureMethod: captureMethod,
      executionMethod: .string(executionMethod),
    ))
  }

  /// `normalizeObservation`: the replacement or payload, read into the
  /// observation shape with the legacy fallbacks; nil when it is falsy.
  static func normalizedObservation(_ event: EvidenceEvent) throws(EvidenceEventError)
    -> JSONObject?
  {
    let payload = JavaScriptValue.coalesce(event["replacement"], event["payload"])
    guard JavaScriptValue.isTruthy(payload) else {
      return nil
    }
    func member(_ key: String) -> JSONValue? {
      JavaScriptValue.member(payload, key)
    }

    var observation = JSONObject()
    observation["targets"] = try targets(
      member("targets"),
      useCaseIdentifiers: member("use_case_ids"),
    )
    observation["kind"] = JavaScriptValue.coalesce(
      member("kind"),
      JavaScriptValue.coalesce(member("evidence_kind"), .string("manual_observation")),
    )
    observation["captured_at"] = JavaScriptValue.coalesce(
      member("captured_at"),
      event["recorded_at"],
    )
    let verdict = member("verdict")
    let verdictResult: JSONValue = JavaScriptValue.strictlyEquals(verdict, "pass")
      || JavaScriptValue.strictlyEquals(verdict, "fail") ? verdict ?? .null : .string("observed")
    observation["result"] = JavaScriptValue.coalesce(member("result"), verdictResult)
    observation["summary"] = member("summary")
    var fallbackProducer = JSONObject()
    fallbackProducer["type"] = JavaScriptValue.coalesce(
      JavaScriptValue.member(member("verifier"), "type"),
      event["actor_type"],
    )
    observation["producer"] = JavaScriptValue.coalesce(
      member("producer"),
      .object(fallbackProducer),
    )
    observation["method"] = JavaScriptValue.coalesce(
      member("method"),
      .object(JSONObject([("type", .string("reported"))])),
    )
    observation["evidence_kind"] = member("evidence_kind")
    observation["use_case_ids"] = member("use_case_ids")
    observation["verifier"] = member("verifier")
    observation["verdict"] = verdict
    return observation
  }

  /// `payload.targets ?? (payload.use_case_ids ?? []).map(...)`.
  private static func targets(
    _ targets: JSONValue?,
    useCaseIdentifiers: JSONValue?,
  ) throws(EvidenceEventError) -> JSONValue? {
    guard JavaScriptValue.isNullish(targets) else {
      return targets
    }
    guard !JavaScriptValue.isNullish(useCaseIdentifiers) else {
      return .array([])
    }
    guard let identifiers = useCaseIdentifiers?.arrayValue else {
      throw .unreadableEvent(message: "(payload.use_case_ids ?? []).map is not a function")
    }
    return .array(identifiers.map { identifier in
      .object(JSONObject([
        ("use_case_id", identifier),
        ("use_case_semantic_hash", .string(zeroHash)),
      ]))
    })
  }

  /// `===` on an event type: Swift's `switch` on strings is canonical
  /// equivalence, so each case also checks the code units.
  private static func isExactly(
    _ value: String,
    _ expected: String,
  ) -> Bool {
    JavaScriptString.identical(value, expected)
  }

  private mutating func report(
    _ code: String,
    _ message: String,
  ) {
    diagnostics.append(Diagnostic(
      code: code,
      message: message,
      entityIdentifier: aggregateIdentifier,
    ))
  }

  private mutating func rejected(
    _ code: String,
    _ message: String,
  ) -> EvidenceAggregateState {
    report(code, message)
    return invalid()
  }

  /// `invalidAggregate`.
  private func invalid() -> EvidenceAggregateState {
    EvidenceAggregateState(
      evidenceIdentifier: aggregateIdentifier,
      status: .invalid,
      effectiveObservation: nil,
      targetLinks: [],
      assurance: JSONObject(),
      freshnessInputs: JSONObject([("use_case_semantic_hashes", .array([]))]),
      eventIdentifiers: events.map(\.eventIdentifier),
      replacementEvidenceIdentifier: nil,
    )
  }
}
