import { canonicalJson } from "../markers/canonicalJson.js";
import type { Diagnostic } from "../schema/index.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import { deriveEvidenceAssurance } from "./assurance.js";
import { diagnostic, readEvidenceLedgers } from "./jsonlLedger.js";
import type { EvidenceAggregateState, EvidenceEvent, EvidenceObservation, EvidenceSnapshot } from "./types.js";

export function replayEvidence(options: { context: ResolvedWorkspaceContext }): EvidenceSnapshot {
  const read = readEvidenceLedgers(options.context);
  const diagnostics = [...read.diagnostics];
  const uniqueEvents = dedupeEvents(read.events, diagnostics);
  const grouped = groupByAggregate(uniqueEvents.events);
  const invalidAggregates = new Set(uniqueEvents.invalidAggregates);
  const aggregates = Array.from(grouped.entries())
    .map(([aggregateId, events]) => projectAggregate(aggregateId, events, diagnostics, invalidAggregates))
    .sort((left, right) => left.evidenceId.localeCompare(right.evidenceId));

  markSupersessionCycles(aggregates, diagnostics);

  const invalidAggregateCount = aggregates.filter((item) => item.status === "invalid").length;
  const tornTailCount = read.ledgers.filter((ledger) => ledger.torn_tail).length;
  const unknownScopeDamage = read.ledgers.some((ledger) => ledger.unknown_scope_damage);
  const complete = diagnostics.length === 0 && invalidAggregateCount === 0 && tornTailCount === 0 && !unknownScopeDamage;
  const activeCount = aggregates.filter((item) => item.status === "active").length;
  const state = complete ? "clean" : activeCount > 0 ? "partial" : "unusable";

  return {
    complete,
    integrity: {
      state,
      unknownScopeDamage,
      invalidAggregateCount,
      tornTailCount
    },
    ledgers: read.ledgers,
    aggregates,
    diagnostics,
    counts: {
      ledgers: read.ledgers.length,
      events_loaded: uniqueEvents.events.length,
      aggregates_total: aggregates.length,
      aggregates_active: activeCount,
      aggregates_invalid: invalidAggregateCount
    },
    events: uniqueEvents.events
  };
}

function dedupeEvents(events: EvidenceEvent[], diagnostics: Diagnostic[]): {
  events: EvidenceEvent[];
  invalidAggregates: Set<string>;
} {
  const byEventId = new Map<string, EvidenceEvent>();
  const invalidAggregates = new Set<string>();
  const kept: EvidenceEvent[] = [];
  for (const event of events) {
    const previous = byEventId.get(event.event_id);
    if (!previous) {
      byEventId.set(event.event_id, event);
      kept.push(event);
      continue;
    }
    if (canonicalJson(previous) === canonicalJson(event)) {
      diagnostics.push(diagnostic("evidence_duplicate_event_id", "Duplicate identical event ID projected once.", nullPath(event), event.aggregate_id));
      continue;
    }
    invalidAggregates.add(previous.aggregate_id);
    invalidAggregates.add(event.aggregate_id);
    diagnostics.push(diagnostic("evidence_duplicate_event_id", "Conflicting duplicate event ID.", nullPath(event), event.aggregate_id));
  }
  return { events: kept, invalidAggregates };
}

function projectAggregate(
  aggregateId: string,
  events: EvidenceEvent[],
  diagnostics: Diagnostic[],
  invalidAggregates: Set<string>
): EvidenceAggregateState {
  const eventIds = events.map((event) => event.event_id);
  if (invalidAggregates.has(aggregateId)) {
    return invalidAggregate(aggregateId, eventIds);
  }
  const sequences = new Map<number, EvidenceEvent[]>();
  for (const event of events) {
    const current = sequences.get(event.sequence) ?? [];
    current.push(event);
    sequences.set(event.sequence, current);
  }
  if (Array.from(sequences.values()).some((items) => items.length > 1)) {
    diagnostics.push(diagnostic("evidence_sequence_conflict", "Duplicate aggregate sequence.", null, aggregateId));
    return invalidAggregate(aggregateId, eventIds);
  }
  const ordered = events.slice().sort((left, right) => left.sequence - right.sequence);
  for (let index = 0; index < ordered.length; index += 1) {
    if (ordered[index].sequence !== index + 1) {
      diagnostics.push(diagnostic("evidence_sequence_gap", "Aggregate sequence must start at 1 and be contiguous.", null, aggregateId));
      return invalidAggregate(aggregateId, eventIds);
    }
  }
  if (ordered.filter((event) => event.event_type === "evidence_recorded").length !== 1 || ordered[0]?.event_type !== "evidence_recorded") {
    diagnostics.push(diagnostic("evidence_invalid_transition", "Aggregate must contain exactly one initial evidence_recorded event.", null, aggregateId));
    return invalidAggregate(aggregateId, eventIds);
  }

  let head = ordered[0];
  let observation = normalizeObservation(ordered[0]);
  let status: EvidenceAggregateState["status"] = "active";
  let replacementEvidenceId: string | undefined;

  for (const event of ordered.slice(1)) {
    if (event.target_event_id !== head.event_id) {
      diagnostics.push(diagnostic("evidence_invalid_transition", "Event must target the current aggregate head.", null, aggregateId));
      return invalidAggregate(aggregateId, eventIds);
    }
    if (event.event_type === "evidence_corrected") {
      if (!event.replacement || event.sequence <= head.sequence) {
        diagnostics.push(diagnostic("evidence_invalid_transition", "Correction must contain a replacement and target an earlier head.", null, aggregateId));
        return invalidAggregate(aggregateId, eventIds);
      }
      observation = normalizeObservation(event);
      head = event;
      continue;
    }
    if (event.event_type === "evidence_voided") {
      status = "voided";
      head = event;
      break;
    }
    if (event.event_type === "evidence_invalidated") {
      status = "invalidated";
      head = event;
      break;
    }
    if (event.event_type === "evidence_superseded") {
      if (event.replacement_evidence_id === aggregateId) {
        diagnostics.push(diagnostic("evidence_supersession_cycle", "Evidence cannot supersede itself.", null, aggregateId));
        return invalidAggregate(aggregateId, eventIds);
      }
      status = "superseded";
      replacementEvidenceId = event.replacement_evidence_id;
      head = event;
      break;
    }
  }

  return {
    evidenceId: aggregateId,
    status,
    effectiveObservation: observation,
    targetLinks: observation?.targets ?? [],
    assurance: observation
      ? deriveEvidenceAssurance({
          kind: observation.kind,
          origin: observation.producer.type,
          captureMethod: observation.method.type === "structured_command" ? "executed" : observation.method.type,
          executionMethod: observation.kind === "test_result" ? "test" : observation.kind === "command_result" ? "command" : "none"
        })
      : {},
    freshnessInputs: {
      captured_at: observation?.captured_at,
      use_case_semantic_hashes: (observation?.targets ?? []).map((target) => target.use_case_semantic_hash),
      explicit_invalidation: status === "invalidated"
    },
    eventIds,
    replacementEvidenceId
  };
}

function normalizeObservation(event: EvidenceEvent): EvidenceObservation | undefined {
  const payload = event.replacement ?? event.payload;
  if (!payload) {
    return undefined;
  }
  return {
    targets:
      payload.targets ??
      (payload.use_case_ids ?? []).map((useCaseId) => ({
        use_case_id: useCaseId,
        use_case_semantic_hash:
          "sha256:0000000000000000000000000000000000000000000000000000000000000000"
      })),
    kind: payload.kind ?? payload.evidence_kind ?? "manual_observation",
    captured_at: payload.captured_at ?? event.recorded_at,
    result:
      payload.result ??
      (payload.verdict === "pass" || payload.verdict === "fail" ? payload.verdict : "observed"),
    summary: payload.summary,
    producer: payload.producer ?? { type: payload.verifier?.type ?? event.actor_type },
    method: payload.method ?? { type: "reported" },
    evidence_kind: payload.evidence_kind,
    use_case_ids: payload.use_case_ids,
    verifier: payload.verifier,
    verdict: payload.verdict
  };
}

function markSupersessionCycles(aggregates: EvidenceAggregateState[], diagnostics: Diagnostic[]): void {
  const byId = new Map(aggregates.map((aggregate) => [aggregate.evidenceId, aggregate]));
  for (const aggregate of aggregates) {
    const seen = new Set<string>();
    let cursor: EvidenceAggregateState | undefined = aggregate;
    while (cursor?.replacementEvidenceId) {
      if (seen.has(cursor.evidenceId)) {
        for (const id of seen) {
          const affected = byId.get(id);
          if (affected) {
            affected.status = "invalid";
          }
        }
        diagnostics.push(diagnostic("evidence_supersession_cycle", "Supersession graph contains a cycle.", null, aggregate.evidenceId));
        break;
      }
      seen.add(cursor.evidenceId);
      cursor = byId.get(cursor.replacementEvidenceId);
    }
  }
}

function invalidAggregate(evidenceId: string, eventIds: string[]): EvidenceAggregateState {
  return {
    evidenceId,
    status: "invalid",
    targetLinks: [],
    assurance: {},
    freshnessInputs: { use_case_semantic_hashes: [] },
    eventIds
  };
}

function groupByAggregate(events: EvidenceEvent[]): Map<string, EvidenceEvent[]> {
  const grouped = new Map<string, EvidenceEvent[]>();
  for (const event of events) {
    const current = grouped.get(event.aggregate_id) ?? [];
    current.push(event);
    grouped.set(event.aggregate_id, current);
  }
  return grouped;
}

function nullPath(_event: EvidenceEvent): string | null {
  return null;
}

