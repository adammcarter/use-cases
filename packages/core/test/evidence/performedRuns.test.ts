// The other half of the measured defect: the acceptance claim ignored the one
// ledger that recorded behaviour actually being driven.
//
// Two ledgers existed side by side. `.use-cases/verification-results.jsonl` —
// hand-editable, and the only thing the claim read. `evidence/by-id/**` — the
// append-only record of what was observed, which the claim ignored entirely. So
// five genuine hand-drive records against a shipped binary moved the number by
// zero, while one typed line moved it by one.
//
// `collectPerformedRuns` picks out the evidence the claim may honestly count: a
// run THE TOOL ITSELF executed, still current against the row it targets. A
// self-reported "I tried it and it worked" stays exactly what the ledger already
// called it — the weakest tier — and never becomes proof.
import { describe, expect, test } from "vitest";
import { collectPerformedRuns } from "../../src/evidence/performedRuns.js";
import type {
  EvidenceAggregateState,
  EvidenceObservation,
  EvidenceSnapshot
} from "../../src/evidence/types.js";

const ROW = "checkout.apply_coupon";
const HASH = `sha256:${"a".repeat(64)}`;
const OTHER_HASH = `sha256:${"b".repeat(64)}`;

function observation(overrides: Partial<EvidenceObservation> = {}): EvidenceObservation {
  return {
    targets: [{ use_case_id: ROW, use_case_semantic_hash: HASH }],
    kind: "command_result",
    captured_at: "2026-06-28T12:00:00.000Z",
    result: "pass",
    summary: "Drove the shipped binary and read its output.",
    producer: { type: "script" },
    method: { type: "structured_command", executable: "node", argv: ["node", "dist/cli.js", "--version"] },
    verdict: "pass",
    ...overrides
  };
}

function aggregate(overrides: Partial<EvidenceAggregateState> = {}): EvidenceAggregateState {
  const effective = overrides.effectiveObservation ?? observation();
  return {
    evidenceId: "01JEVIDENCE0000000000000000",
    status: "active",
    effectiveObservation: effective,
    targetLinks: effective.targets,
    assurance: {
      origin: "script",
      capture_method: "executed",
      execution_method: "command",
      integrity: "tool_computed_digest",
      reproducibility: "structured_command",
      result: "pass",
      class: "reproducible"
    },
    freshnessInputs: { use_case_semantic_hashes: [HASH] },
    eventIds: ["01JEVIDENCE0000000000000000"],
    ...overrides
  };
}

function snapshot(aggregates: EvidenceAggregateState[]): EvidenceSnapshot {
  return {
    complete: true,
    integrity: {
      state: "clean",
      unknownScopeDamage: false,
      invalidAggregateCount: 0,
      tornTailCount: 0
    },
    ledgers: [],
    aggregates,
    diagnostics: [],
    events: []
  } as unknown as EvidenceSnapshot;
}

const current = new Map([[ROW, HASH]]);

function rowsOf(aggregates: EvidenceAggregateState[]): string[] {
  return collectPerformedRuns(snapshot(aggregates), current).map((run) => run.row_id);
}

describe("collectPerformedRuns", () => {
  test("a run the tool executed against the current row counts", () => {
    expect(rowsOf([aggregate()])).toEqual([ROW]);
  });

  // The discriminator. `use-cases evidence record` without --run writes a self-reported
  // observation: an agent's word that something happened. The ledger already
  // grades it the weakest tier, and the claim must respect that grading rather
  // than counting every row anyone wrote a sentence about.
  test("a SELF-REPORTED observation never counts, however confident", () => {
    const reported = aggregate({
      effectiveObservation: observation({
        producer: { type: "agent" },
        method: { type: "reported" }
      }),
      assurance: {
        origin: "agent",
        capture_method: "reported",
        execution_method: "none",
        integrity: "none",
        reproducibility: "none",
        result: "pass",
        class: "reported"
      }
    });
    expect(rowsOf([reported])).toEqual([]);
  });

  // argv is the tell. Only a tool that SPAWNED something knows the argv it
  // spawned; a hand-written record can claim `structured_command` but has no
  // command to name.
  test("a structured_command claim with no argv does not count", () => {
    const claimed = aggregate({
      effectiveObservation: observation({ method: { type: "structured_command" } })
    });
    expect(rowsOf([claimed])).toEqual([]);
  });

  // A record can NAME a command without the tool having executed it: a human who
  // watched a command run and wrote down its argv lands at capture_method
  // "observed", class `observed`. That is a real observation and it is still not
  // a run the tool performed, so it does not prove the row.
  //
  // Isolating this mattered: a first version of the suite let the argv check
  // stand in for the class check, and deleting the class check broke nothing.
  test("an OBSERVED command — argv and all — is not a run the tool executed", () => {
    const watched = aggregate({
      assurance: {
        origin: "user",
        capture_method: "observed",
        execution_method: "manual",
        integrity: "caller_reported_digest",
        reproducibility: "instructions",
        result: "pass",
        class: "observed"
      }
    });
    expect(rowsOf([watched])).toEqual([]);
  });

  test("a FAILING run does not count as proof the behaviour holds", () => {
    const failed = aggregate({
      effectiveObservation: observation({ result: "fail", verdict: "fail" })
    });
    expect(rowsOf([failed])).toEqual([]);
  });

  test("a voided record does not count", () => {
    expect(rowsOf([aggregate({ status: "voided" })])).toEqual([]);
  });

  // The freshness analogue for this tier: edit the row and the run that proved
  // the OLD row stops proving the new one. Without this, a performed run would
  // be the one tier in the system that never goes stale.
  test("a run recorded against a since-edited row does not count", () => {
    const drifted = aggregate({
      effectiveObservation: observation({
        targets: [{ use_case_id: ROW, use_case_semantic_hash: OTHER_HASH }]
      })
    });
    expect(rowsOf([drifted])).toEqual([]);
  });

  test("a run targeting a row that is no longer in the matrix does not count", () => {
    const orphan = aggregate({
      effectiveObservation: observation({
        targets: [{ use_case_id: "checkout.deleted", use_case_semantic_hash: HASH }]
      })
    });
    expect(rowsOf([orphan])).toEqual([]);
  });

  test("one row driven twice is reported once", () => {
    expect(rowsOf([aggregate(), aggregate({ evidenceId: "01JEVIDENCE0000000000000002" })])).toEqual([
      ROW
    ]);
  });
});
