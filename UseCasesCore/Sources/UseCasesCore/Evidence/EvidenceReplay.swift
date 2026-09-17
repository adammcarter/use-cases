/// Replays the evidence history into aggregates
/// (packages/core/src/evidence/replayEvidence.ts).
///
/// Events are de-duplicated by id, grouped by aggregate in first-seen order,
/// projected, sorted by evidence id with `localeCompare`, and checked for
/// supersession cycles. Every diagnostic lands in that order.
public enum EvidenceReplay {
  public static func replay(context: ResolvedWorkspaceContext) throws(EvidenceEventError)
    -> EvidenceSnapshot
  {
    let read = try EvidenceLedgerReader.read(context: context)
    var diagnostics = read.diagnostics
    let unique = try deduplicated(read.events, diagnostics: &diagnostics)

    var grouped = OrderedStringMap<[EvidenceEvent]>()
    for event in unique.events {
      grouped[event.aggregateIdentifier] = (grouped[event.aggregateIdentifier] ?? []) + [event]
    }
    var aggregates: [EvidenceAggregateState] = []
    for group in grouped.pairs {
      var projection = EvidenceAggregateProjection(
        aggregateIdentifier: group.key,
        events: group.value,
        isInvalid: unique.invalidAggregates.contains(group.key),
      )
      try aggregates.append(projection.project())
      diagnostics += projection.diagnostics
    }
    aggregates.sort { left, right in
      JavaScriptStringOrder.localeAscending(left.evidenceIdentifier, right.evidenceIdentifier)
    }
    markSupersessionCycles(&aggregates, diagnostics: &diagnostics)

    return snapshot(
      read: read,
      aggregates: aggregates,
      diagnostics: diagnostics,
      events: unique.events,
    )
  }

  private static func snapshot(
    read: EvidenceLedgerReadResult,
    aggregates: [EvidenceAggregateState],
    diagnostics: [Diagnostic],
    events: [EvidenceEvent],
  ) -> EvidenceSnapshot {
    let invalidCount = aggregates.count { $0.status == .invalid }
    let tornTailCount = read.ledgers.count(where: \.hasTornTail)
    let hasUnknownScopeDamage = read.ledgers.contains(where: \.hasUnknownScopeDamage)
    let isComplete = diagnostics.isEmpty && invalidCount == 0 && tornTailCount == 0
      && !hasUnknownScopeDamage
    let activeCount = aggregates.count { $0.status == .active }
    let state: EvidenceIntegrityState = isComplete ? .clean : activeCount > 0 ? .partial : .unusable
    return EvidenceSnapshot(
      isComplete: isComplete,
      integrity: EvidenceIntegrity(
        state: state,
        hasUnknownScopeDamage: hasUnknownScopeDamage,
        invalidAggregateCount: invalidCount,
        tornTailCount: tornTailCount,
      ),
      ledgers: read.ledgers,
      aggregates: aggregates,
      diagnostics: diagnostics,
      counts: EvidenceCounts(
        ledgers: read.ledgers.count,
        eventsLoaded: events.count,
        aggregatesTotal: aggregates.count,
        aggregatesActive: activeCount,
        aggregatesInvalid: invalidCount,
      ),
      events: events,
    )
  }

  /// `dedupeEvents`: the first event with an id is kept; a later identical one
  /// is projected once, a later different one invalidates both aggregates.
  private static func deduplicated(
    _ events: [EvidenceEvent],
    diagnostics: inout [Diagnostic],
  ) throws(EvidenceEventError) -> (events: [EvidenceEvent], invalidAggregates: OrderedStringSet) {
    var byEventIdentifier = OrderedStringMap<EvidenceEvent>()
    var invalidAggregates = OrderedStringSet()
    var kept: [EvidenceEvent] = []
    for event in events {
      guard let previous = byEventIdentifier[event.eventIdentifier] else {
        byEventIdentifier[event.eventIdentifier] = event
        kept.append(event)
        continue
      }
      if try JavaScriptString.identical(canonical(previous), canonical(event)) {
        diagnostics.append(Diagnostic(
          code: "evidence_duplicate_event_id",
          message: "Duplicate identical event ID projected once.",
          entityIdentifier: event.aggregateIdentifier,
        ))
        continue
      }
      invalidAggregates.insert(previous.aggregateIdentifier)
      invalidAggregates.insert(event.aggregateIdentifier)
      diagnostics.append(Diagnostic(
        code: "evidence_duplicate_event_id",
        message: "Conflicting duplicate event ID.",
        entityIdentifier: event.aggregateIdentifier,
      ))
    }
    return (kept, invalidAggregates)
  }

  private static func canonical(_ event: EvidenceEvent) throws(EvidenceEventError) -> String {
    do throws(CodeUnitCanonicalJSONError) {
      return try CodeUnitCanonicalJSON.encode(event.jsonValue)
    } catch {
      throw .nonFiniteNumber
    }
  }

  /// `markSupersessionCycles`: following each aggregate's replacement chain,
  /// every aggregate seen before one repeats is marked invalid.
  private static func markSupersessionCycles(
    _ aggregates: inout [EvidenceAggregateState],
    diagnostics: inout [Diagnostic],
  ) {
    var positions = OrderedStringMap<Int>()
    for (position, aggregate) in aggregates.enumerated() {
      positions[aggregate.evidenceIdentifier] = position
    }
    for start in aggregates.indices {
      var seen = OrderedStringSet()
      var cursor: Int? = start
      while let current = cursor,
            JavaScriptValue.isTruthy(aggregates[current].replacementEvidenceIdentifier)
      {
        let identifier = aggregates[current].evidenceIdentifier
        if seen.contains(identifier) {
          for member in seen.members {
            if let position = positions[member] {
              aggregates[position].status = .invalid
            }
          }
          diagnostics.append(Diagnostic(
            code: "evidence_supersession_cycle",
            message: "Supersession graph contains a cycle.",
            entityIdentifier: aggregates[start].evidenceIdentifier,
          ))
          break
        }
        seen.insert(identifier)
        cursor = aggregates[current].replacementEvidenceIdentifier?.stringValue
          .flatMap { positions[$0] }
      }
    }
  }
}
