// Acceptance test for use-case row
//   presentation_skills.evidence.append_only_corrections
//
// The row promises: corrections to evidence are made by APPENDING events (void,
// supersede, correct) — never by silently rewriting or deleting prior history —
// and an append that does not target the aggregate's CURRENT head is refused.
//
// It drives the REAL append-only ledger primitives the bound code implements
// (packages/ucm-core/src/evidence/appendEvidenceEvent.ts: appendEvidenceVoidEvent
// / voidUnderLock) against a temp copy of the `evidence-basic` fixture and asserts
// the two observable outcomes:
//
//   1. A void event referencing the wrong head is REFUSED
//      (evidence_expected_head_mismatch) — an agent cannot blind-rewrite history.
//   2. A correct-head void is APPENDED, and replaying the ledger keeps the prior
//      recorded event visible (history retained) while flipping current status to
//      "voided" — the correction is additive, not destructive.
import { cpSync, mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../packages/ucm-core/src/roots.js";
import { loadUseCaseMatrix } from "../../packages/ucm-core/src/useCases/loadUseCaseMatrix.js";
import {
  appendEvidenceEvent,
  appendEvidenceVoidEvent,
  replayEvidence
} from "../../packages/ucm-core/src/evidence/index.js";
import { rmSync } from "node:fs";

const repoRoot = resolve(import.meta.dirname, "../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");
const USE_CASE_ID = "showcase.live.golden";

const tempDirs: string[] = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function freshWorkspace(): string {
  const dir = mkdtempSync(join(tmpdir(), "ucp-append-only-"));
  cpSync(join(fixturesRoot, "evidence-basic"), dir, { recursive: true });
  tempDirs.push(dir);
  return dir;
}

function semanticHash(workspaceRoot: string): string {
  const matrix = loadUseCaseMatrix({ context: resolveWorkspaceContext({ workspaceRoot }) });
  const resolved = matrix.resolveUseCase(USE_CASE_ID);
  if (resolved.kind !== "resolved") {
    throw new Error(`fixture use case ${USE_CASE_ID} did not resolve`);
  }
  return resolved.useCase.semanticHash;
}

describe("append_only_corrections", () => {
  test("a wrong-head void is refused; a correct-head void is appended and keeps history", () => {
    const workspaceRoot = freshWorkspace();
    const context = resolveWorkspaceContext({ workspaceRoot });

    const recorded = appendEvidenceEvent({
      context,
      idempotencyKey: "record-1",
      target: { use_case_id: USE_CASE_ID, use_case_semantic_hash: semanticHash(workspaceRoot) },
      kind: "manual_observation",
      result: "pass",
      summary: "Observed the live showcase.",
      actorType: "user",
      hostSurface: "codex.cli"
    });
    expect(recorded.appended).toBe(true);
    const evidenceId = recorded.event.aggregate_id;
    const head = recorded.event.event_id;

    // (1) A void that does not reference the CURRENT head must be refused — an
    //     agent cannot rewrite the ledger by guessing or supplying a stale head.
    expect(() =>
      appendEvidenceVoidEvent({
        context,
        evidenceId,
        expectedHeadEventId: "01900000-0000-7000-8000-000000000000",
        reason: "attempted blind rewrite",
        idempotencyKey: "void-wrong-head",
        actorType: "agent",
        hostSurface: "codex.cli"
      })
    ).toThrow(/expected head/i);

    // The aggregate is untouched by the refused attempt: still one active event.
    const afterRefusal = replayEvidence({ context });
    const beforeVoid = afterRefusal.aggregates.find((item) => item.evidenceId === evidenceId);
    expect(beforeVoid?.status).toBe("active");
    expect(beforeVoid?.eventIds).toHaveLength(1);

    // (2) A correct-head void is appended.
    const voided = appendEvidenceVoidEvent({
      context,
      evidenceId,
      expectedHeadEventId: head,
      reason: "Superseded by a later observation.",
      idempotencyKey: "void-correct-head",
      actorType: "agent",
      hostSurface: "codex.cli"
    });
    expect(voided.appended).toBe(true);
    expect(voided.event.event_type).toBe("evidence_voided");

    const afterVoid = replayEvidence({ context });
    const aggregate = afterVoid.aggregates.find((item) => item.evidenceId === evidenceId);
    // History is retained additively: the original recorded event is still there,
    // the void is layered on top, and current status reflects the correction.
    expect(aggregate?.status).toBe("voided");
    expect(aggregate?.eventIds).toEqual([head, voided.event.event_id]);
  });
});
