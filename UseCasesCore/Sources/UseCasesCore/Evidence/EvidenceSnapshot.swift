/// An aggregate's projected status.
public enum EvidenceAggregateStatus: String, CaseIterable, Sendable {
  case active
  case voided
  case invalidated
  case superseded
  case invalid
}

/// How usable the whole history is.
public enum EvidenceIntegrityState: String, CaseIterable, Sendable {
  case clean
  case partial
  case unusable
}

/// One piece of evidence, projected from its events.
///
/// The observation, assurance and freshness inputs are built from ledger data
/// that nothing validated past the event shape, so they are kept as the JSON
/// the TypeScript builds: members in its order, `undefined` members left out.
public struct EvidenceAggregateState: Sendable, Equatable {
  public let evidenceIdentifier: String
  public internal(set) var status: EvidenceAggregateStatus
  public let effectiveObservation: JSONObject?
  public let targetLinks: [JSONValue]
  public let assurance: JSONObject
  public let freshnessInputs: JSONObject
  public let eventIdentifiers: [String]
  /// The superseding event's `replacement_evidence_id` as written — any JSON,
  /// or nil when absent.
  public let replacementEvidenceIdentifier: JSONValue?
}

public struct EvidenceIntegrity: Sendable, Equatable {
  public let state: EvidenceIntegrityState
  public let hasUnknownScopeDamage: Bool
  public let invalidAggregateCount: Int
  public let tornTailCount: Int
}

public struct EvidenceCounts: Sendable, Equatable {
  public let ledgers: Int
  public let eventsLoaded: Int
  public let aggregatesTotal: Int
  public let aggregatesActive: Int
  public let aggregatesInvalid: Int

  /// `{ ledgers, events_loaded, aggregates_total, aggregates_active,
  /// aggregates_invalid }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("ledgers", .number(Double(ledgers))),
      ("events_loaded", .number(Double(eventsLoaded))),
      ("aggregates_total", .number(Double(aggregatesTotal))),
      ("aggregates_active", .number(Double(aggregatesActive))),
      ("aggregates_invalid", .number(Double(aggregatesInvalid))),
    ]))
  }
}

/// The replayed evidence history.
public struct EvidenceSnapshot: Sendable, Equatable {
  public let isComplete: Bool
  public let integrity: EvidenceIntegrity
  public let ledgers: [EvidenceLedgerResult]
  public let aggregates: [EvidenceAggregateState]
  public let diagnostics: [Diagnostic]
  public let counts: EvidenceCounts
  /// Every loaded event, duplicates projected once.
  public let events: [EvidenceEvent]

  /// `toEvidenceStatusResult`: the `evidence-status-result` wire data.
  public func statusResult() -> JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("integrity", .object(JSONObject([
        ("state", .string(integrity.state.rawValue)),
        ("unknown_scope_damage", .bool(integrity.hasUnknownScopeDamage)),
        ("invalid_aggregate_count", .number(Double(integrity.invalidAggregateCount))),
        ("torn_tail_count", .number(Double(integrity.tornTailCount))),
      ]))),
      ("ledgers", .array(ledgers.map(\.jsonValue))),
      ("aggregates", .array(aggregates.map { aggregate in
        .object(JSONObject([
          ("evidence_id", .string(aggregate.evidenceIdentifier)),
          ("status", .string(aggregate.status.rawValue)),
          ("event_ids", .array(aggregate.eventIdentifiers.map(JSONValue.string))),
          ("target_links", .array(aggregate.targetLinks)),
          ("assurance", .object(aggregate.assurance)),
          ("freshness_inputs", .object(aggregate.freshnessInputs)),
        ]))
      })),
      ("counts", counts.jsonValue),
    ]))
  }
}
