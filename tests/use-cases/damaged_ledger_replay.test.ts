// Acceptance test for use-case row
//   presentation_skills.evidence.damaged_ledger_replay
//
// The row promises: a partially corrupted JSONL evidence ledger is replayed
// tolerantly — valid events are KEPT, damaged lines (unparseable JSON, an
// unterminated/torn final line) are surfaced as diagnostics, and integrity is
// reported as partial rather than silently clean. A neighbouring damaged line
// must never cause valid proof to be discarded.
//
// It drives the REAL tolerant reader the bound code implements
// (packages/core/src/evidence/jsonlLedger.ts: readLedgerFile) through
// replayEvidence over a temp copy of the `evidence-basic` fixture whose ledger
// contains one valid event, one parse-error line, and a torn tail.
import { cpSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../packages/core/src/roots.js";
import { replayEvidence } from "../../packages/core/src/evidence/index.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");

const tempDirs: string[] = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function freshWorkspace(): string {
  const dir = mkdtempSync(join(tmpdir(), "ucp-damaged-replay-"));
  cpSync(join(fixturesRoot, "evidence-basic"), dir, { recursive: true });
  tempDirs.push(dir);
  return dir;
}

const VALID_EVENT = {
  schema_version: 1,
  event_type: "evidence_recorded",
  event_id: "01900000-0000-7000-8000-000000000001",
  aggregate_id: "01900000-0000-7000-8000-000000000001",
  sequence: 1,
  recorded_at: "2026-06-25T12:00:00.000Z",
  actor_type: "agent",
  host_surface: "codex.cli",
  idempotency_key: "valid-line",
  intent_digest: "sha256:1111111111111111111111111111111111111111111111111111111111111111",
  payload: {
    targets: [
      {
        use_case_id: "showcase.live.golden",
        use_case_semantic_hash:
          "sha256:2222222222222222222222222222222222222222222222222222222222222222"
      }
    ],
    kind: "manual_observation",
    captured_at: "2026-06-25T12:00:00.000Z",
    result: "pass",
    summary: "Observed.",
    producer: { type: "agent", identity: "fixture" },
    method: { type: "reported" }
  }
};

describe("damaged_ledger_replay", () => {
  test("valid events survive a neighbouring parse error and a torn final line", () => {
    const workspaceRoot = freshWorkspace();
    const context = resolveWorkspaceContext({ workspaceRoot });

    const ledgerPath = join(
      workspaceRoot,
      "evidence/by-id/01/01900000-0000-7000-8000-000000000001.jsonl"
    );
    mkdirSync(dirname(ledgerPath), { recursive: true });
    // line 1: a valid event; line 2: unparseable JSON; line 3: a torn final line
    // (no trailing newline) — three classes of content in one ledger.
    writeFileSync(
      ledgerPath,
      `${JSON.stringify(VALID_EVENT)}\n{ this is not json }\n{"schema_version":1`
    );

    const snapshot = replayEvidence({ context });

    // Integrity is partial, not silently clean.
    expect(snapshot.complete).toBe(false);
    expect(snapshot.integrity.tornTailCount).toBeGreaterThanOrEqual(1);

    // The valid event is NOT discarded because of the damaged neighbours.
    expect(snapshot.aggregates.map((item) => item.evidenceId)).toContain(
      "01900000-0000-7000-8000-000000000001"
    );

    // Both damage classes surface as actionable diagnostics.
    const codes = snapshot.diagnostics.map((diagnostic) => diagnostic.code);
    expect(codes).toContain("evidence_parse_error");
    expect(codes).toContain("evidence_torn_tail");
  });
});
