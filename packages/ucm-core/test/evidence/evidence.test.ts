import { cpSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/roots.js";
import { loadUseCaseMatrix } from "../../src/useCases/loadUseCaseMatrix.js";
import {
  appendEvidenceEvent,
  deriveEvidenceAssurance,
  evaluateEvidenceFreshness,
  linkEvidenceToMatrix,
  replayEvidence,
  toEvidenceStatusResult
} from "../../src/evidence/index.js";

const repoRoot = resolve(import.meta.dirname, "../../../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

describe("P3 evidence replay", () => {
  test("replaying the same JSONL twice returns identical derived state", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    writeEvidenceLedger(
      workspaceRoot,
      "evidence/by-id/01/01900000-0000-7000-8000-000000000001.jsonl",
      [recordedEvent()]
    );

    const first = toEvidenceStatusResult(replayEvidence({ context }));
    const second = toEvidenceStatusResult(replayEvidence({ context }));

    expect(second).toEqual(first);
    expect(first).toMatchObject({
      complete: true,
      integrity: {
        state: "clean",
        unknown_scope_damage: false,
        invalid_aggregate_count: 0,
        torn_tail_count: 0
      },
      counts: {
        aggregates_total: 1,
        aggregates_active: 1
      }
    });
  });

  test("a crash-truncated final line warns, stays incomplete, and does not crash", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const ledger = join(
      workspaceRoot,
      "evidence/by-id/01/01900000-0000-7000-8000-000000000001.jsonl"
    );
    mkdirSync(dirname(ledger), { recursive: true });
    writeFileSync(ledger, `${JSON.stringify(recordedEvent())}\n{"schema_version":1`);

    const snapshot = replayEvidence({ context });

    expect(snapshot.complete).toBe(false);
    expect(snapshot.integrity.tornTailCount).toBe(1);
    expect(snapshot.aggregates.map((item) => item.evidenceId)).toEqual([
      "01900000-0000-7000-8000-000000000001"
    ]);
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "evidence_torn_tail",
        source_path: "evidence/by-id/01/01900000-0000-7000-8000-000000000001.jsonl:2"
      })
    );
  });

  test("duplicate aggregate sequence invalidates the aggregate instead of sorting by timestamp", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    writeEvidenceLedger(
      workspaceRoot,
      "evidence/by-id/01/01900000-0000-7000-8000-000000000001.jsonl",
      [
        recordedEvent({ event_id: "01900000-0000-7000-8000-000000000001" }),
        correctedEvent({
          event_id: "01900000-0000-7000-8000-000000000002",
          sequence: 1,
          target_event_id: "01900000-0000-7000-8000-000000000001"
        })
      ]
    );

    const snapshot = replayEvidence({ context });

    expect(snapshot.complete).toBe(false);
    expect(snapshot.aggregates[0]).toMatchObject({
      evidenceId: "01900000-0000-7000-8000-000000000001",
      status: "invalid"
    });
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({
        code: "evidence_sequence_conflict",
        entity_id: "01900000-0000-7000-8000-000000000001"
      })
    );
  });

  test("supersession cycles invalidate affected aggregates", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    writeEvidenceLedger(workspaceRoot, "evidence/by-id/01/a.jsonl", [
      recordedEvent({
        event_id: "01900000-0000-7000-8000-000000000011",
        aggregate_id: "01900000-0000-7000-8000-000000000011"
      }),
      supersededEvent({
        event_id: "01900000-0000-7000-8000-000000000012",
        aggregate_id: "01900000-0000-7000-8000-000000000011",
        sequence: 2,
        target_event_id: "01900000-0000-7000-8000-000000000011",
        replacement_evidence_id: "01900000-0000-7000-8000-000000000021"
      })
    ]);
    writeEvidenceLedger(workspaceRoot, "evidence/by-id/02/b.jsonl", [
      recordedEvent({
        event_id: "01900000-0000-7000-8000-000000000021",
        aggregate_id: "01900000-0000-7000-8000-000000000021"
      }),
      supersededEvent({
        event_id: "01900000-0000-7000-8000-000000000022",
        aggregate_id: "01900000-0000-7000-8000-000000000021",
        sequence: 2,
        target_event_id: "01900000-0000-7000-8000-000000000021",
        replacement_evidence_id: "01900000-0000-7000-8000-000000000011"
      })
    ]);

    const snapshot = replayEvidence({ context });

    expect(snapshot.complete).toBe(false);
    expect(snapshot.aggregates.map((item) => item.status)).toEqual(["invalid", "invalid"]);
    expect(snapshot.diagnostics).toContainEqual(
      expect.objectContaining({ code: "evidence_supersession_cycle" })
    );
  });
});

describe("P3 evidence append and linkage", () => {
  test("same idempotency key and same intent returns the original event without rewriting bytes", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });

    const first = appendEvidenceEvent({
      context,
      idempotencyKey: "same-intent",
      target: {
        use_case_id: "showcase.live.golden",
        use_case_semantic_hash: useCaseHash(workspaceRoot, "showcase.live.golden")
      },
      kind: "manual_observation",
      result: "pass",
      summary: "User observed the live showcase.",
      actorType: "user",
      hostSurface: "codex.cli"
    });
    const bytesAfterFirst = readFileSync(first.ledgerPath, "utf8");
    const second = appendEvidenceEvent({
      context,
      idempotencyKey: "same-intent",
      target: {
        use_case_id: "showcase.live.golden",
        use_case_semantic_hash: useCaseHash(workspaceRoot, "showcase.live.golden")
      },
      kind: "manual_observation",
      result: "pass",
      summary: "User observed the live showcase.",
      actorType: "user",
      hostSurface: "codex.cli"
    });

    expect(second.appended).toBe(false);
    expect(second.event.event_id).toBe(first.event.event_id);
    expect(readFileSync(first.ledgerPath, "utf8")).toBe(bytesAfterFirst);
  });

  test("moving a use-case file does not break stable-ID evidence linkage", () => {
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const context = resolveWorkspaceContext({ workspaceRoot });
    const matrixBeforeMove = loadUseCaseMatrix({ context });
    const useCase = matrixBeforeMove.resolveUseCase("showcase.live.golden");
    if (useCase.kind !== "resolved") {
      throw new Error("fixture use case did not resolve");
    }
    writeEvidenceLedger(
      workspaceRoot,
      "evidence/by-id/01/01900000-0000-7000-8000-000000000001.jsonl",
      [
        recordedEvent({
          payload: {
            ...recordedEvent().payload,
            targets: [
              {
                use_case_id: "showcase.live.golden",
                use_case_semantic_hash: useCase.useCase.semanticHash
              }
            ]
          }
        })
      ]
    );

    mkdirSync(join(workspaceRoot, "use-cases/showcase"), { recursive: true });
    renameSync(
      join(workspaceRoot, "use-cases/showcase-live.yml"),
      join(workspaceRoot, "use-cases/showcase/live.yml")
    );

    const evidence = replayEvidence({ context });
    const matrixAfterMove = loadUseCaseMatrix({ context });
    const links = linkEvidenceToMatrix(evidence, matrixAfterMove);

    expect(links).toContainEqual(
      expect.objectContaining({
        evidenceId: "01900000-0000-7000-8000-000000000001",
        useCaseId: "showcase.live.golden",
        resolution: "resolved",
        semanticHash: "match",
        sourcePath: "use-cases/showcase/live.yml"
      })
    );
  });
});

describe("P3 assurance and freshness", () => {
  test("URL, manual, agent, and executed test evidence produce distinct assurance facets", () => {
    expect(deriveEvidenceAssurance({ kind: "url", origin: "agent", captureMethod: "reported" })).toMatchObject({
      class: "reference"
    });
    expect(
      deriveEvidenceAssurance({ kind: "manual_observation", origin: "user", captureMethod: "observed" })
    ).toMatchObject({ class: "observed" });
    expect(
      deriveEvidenceAssurance({ kind: "agent_observation", origin: "agent", captureMethod: "reported" })
    ).toMatchObject({ class: "reported" });
    expect(
      deriveEvidenceAssurance({
        kind: "test_result",
        origin: "script",
        captureMethod: "executed",
        executionMethod: "test",
        exitStatus: 0
      })
    ).toMatchObject({ class: "reproducible" });
  });

  test("freshness is unknown without an evaluation policy", () => {
    expect(evaluateEvidenceFreshness({ explicitInvalidation: false })).toEqual({
      state: "unknown",
      basis: "missing_evaluation_context"
    });
  });
});

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `presentation-skills-${name}-`));
  cpSync(join(fixturesRoot, name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function writeEvidenceLedger(workspaceRoot: string, relativePath: string, events: unknown[]) {
  const path = join(workspaceRoot, relativePath);
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, `${events.map((event) => JSON.stringify(event)).join("\n")}\n`);
}

function useCaseHash(workspaceRoot: string, id: string): string {
  const matrix = loadUseCaseMatrix({
    context: resolveWorkspaceContext({ workspaceRoot })
  });
  const resolved = matrix.resolveUseCase(id);
  if (resolved.kind !== "resolved") {
    throw new Error(`missing fixture use case ${id}`);
  }
  return resolved.useCase.semanticHash;
}

function recordedEvent(overrides: Record<string, unknown> = {}) {
  return {
    schema_version: 1,
    event_type: "evidence_recorded",
    event_id: "01900000-0000-7000-8000-000000000001",
    aggregate_id: "01900000-0000-7000-8000-000000000001",
    sequence: 1,
    recorded_at: "2026-06-25T12:00:00.000Z",
    actor_type: "agent",
    host_surface: "codex.cli",
    idempotency_key: "fixture-record",
    intent_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
    payload: {
      targets: [
        {
          use_case_id: "showcase.live.golden",
          use_case_semantic_hash: "sha256:2222222222222222222222222222222222222222222222222222222222222222"
        }
      ],
      kind: "manual_observation",
      captured_at: "2026-06-25T12:00:00.000Z",
      result: "pass",
      summary: "Observed.",
      producer: { type: "agent", identity: "fixture" },
      method: { type: "reported" }
    },
    ...overrides
  };
}

function correctedEvent(overrides: Record<string, unknown> = {}) {
  return {
    ...recordedEvent(),
    event_type: "evidence_corrected",
    event_id: "01900000-0000-7000-8000-000000000002",
    sequence: 2,
    target_event_id: "01900000-0000-7000-8000-000000000001",
    reason: "Corrected observation.",
    replacement: {
      ...recordedEvent().payload,
      summary: "Corrected."
    },
    payload: undefined,
    ...overrides
  };
}

function supersededEvent(overrides: Record<string, unknown> = {}) {
  return {
    ...recordedEvent(),
    event_type: "evidence_superseded",
    event_id: "01900000-0000-7000-8000-000000000003",
    sequence: 2,
    target_event_id: "01900000-0000-7000-8000-000000000001",
    replacement_evidence_id: "01900000-0000-7000-8000-000000000099",
    reason: "Superseded by newer proof.",
    payload: undefined,
    ...overrides
  };
}
