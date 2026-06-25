import type { EvidenceAppendResultData, EvidenceSnapshot, EvidenceStatusResultData } from "./types.js";

export function toEvidenceStatusResult(snapshot: EvidenceSnapshot): EvidenceStatusResultData {
  return {
    schema_version: 1,
    complete: snapshot.complete,
    integrity: {
      state: snapshot.integrity.state,
      unknown_scope_damage: snapshot.integrity.unknownScopeDamage,
      invalid_aggregate_count: snapshot.integrity.invalidAggregateCount,
      torn_tail_count: snapshot.integrity.tornTailCount
    },
    ledgers: snapshot.ledgers,
    aggregates: snapshot.aggregates.map((aggregate) => ({
      evidence_id: aggregate.evidenceId,
      status: aggregate.status,
      event_ids: aggregate.eventIds,
      target_links: aggregate.targetLinks,
      assurance: aggregate.assurance,
      freshness_inputs: aggregate.freshnessInputs
    })),
    counts: snapshot.counts
  };
}

export function toEvidenceAppendResult(result: EvidenceAppendResultData): EvidenceAppendResultData {
  return {
    schema_version: 1,
    appended: result.appended,
    event: result.event,
    ledger_path: result.ledger_path,
    durability: result.durability
  };
}
