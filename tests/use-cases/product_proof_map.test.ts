// Acceptance test for use-case row
//   presentation_skills.evidence.product_proof_map
//
// The row promises: recorded proof can be traced from an evidence ID back to a
// stable use-case ID and the row's current semantic hash, and stale/mismatched
// proof is distinguishable from a current match.
//
// It drives the REAL linkage primitive the bound code implements
// (packages/core/src/evidence/linkEvidence.ts: linkEvidenceToMatrix) over a
// temp copy of the `evidence-basic` fixture: evidence is recorded through the real
// append+replay path, then linked against the live matrix. It asserts the three
// resolutions that make the proof map trustworthy — a current "match", a
// "mismatch" when the recorded hash no longer agrees with the row, and "missing"
// when the targeted use case is not in the matrix at all.
import { cpSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../packages/core/src/roots.js";
import { loadUseCaseMatrix } from "../../packages/core/src/useCases/loadUseCaseMatrix.js";
import {
  appendEvidenceEvent,
  linkEvidenceToMatrix,
  replayEvidence
} from "../../packages/core/src/evidence/index.js";

const repoRoot = resolve(import.meta.dirname, "../..");
const fixturesRoot = join(repoRoot, "tests/fixtures/workspaces");
const USE_CASE_ID = "showcase.live.golden";
const BOGUS_HASH = "sha256:0000000000000000000000000000000000000000000000000000000000000000";

const tempDirs: string[] = [];

afterEach(() => {
  for (const dir of tempDirs.splice(0)) {
    rmSync(dir, { recursive: true, force: true });
  }
});

function freshWorkspace(): string {
  const dir = mkdtempSync(join(tmpdir(), "ucp-proof-map-"));
  cpSync(join(fixturesRoot, "evidence-basic"), dir, { recursive: true });
  tempDirs.push(dir);
  return dir;
}

describe("product_proof_map", () => {
  test("evidence links resolve to a matched row, a hash mismatch, and a missing row", () => {
    const workspaceRoot = freshWorkspace();
    const context = resolveWorkspaceContext({ workspaceRoot });
    const matrix = loadUseCaseMatrix({ context });
    const resolved = matrix.resolveUseCase(USE_CASE_ID);
    if (resolved.kind !== "resolved") {
      throw new Error(`fixture use case ${USE_CASE_ID} did not resolve`);
    }

    // A proof recorded against the CURRENT semantic hash -> "match".
    appendEvidenceEvent({
      context,
      idempotencyKey: "match",
      target: { use_case_id: USE_CASE_ID, use_case_semantic_hash: resolved.useCase.semanticHash },
      kind: "test_result",
      result: "pass",
      summary: "Current proof.",
      actorType: "script",
      hostSurface: "codex.cli"
    });
    // A proof recorded against a STALE hash for the same row -> "mismatch".
    appendEvidenceEvent({
      context,
      idempotencyKey: "mismatch",
      target: { use_case_id: USE_CASE_ID, use_case_semantic_hash: BOGUS_HASH },
      kind: "test_result",
      result: "pass",
      summary: "Stale proof.",
      actorType: "script",
      hostSurface: "codex.cli"
    });
    // A proof recorded against a row that is not in the matrix -> "missing".
    appendEvidenceEvent({
      context,
      idempotencyKey: "missing",
      target: { use_case_id: "does.not.exist", use_case_semantic_hash: BOGUS_HASH },
      kind: "test_result",
      result: "pass",
      summary: "Orphan proof.",
      actorType: "script",
      hostSurface: "codex.cli"
    });

    const evidence = replayEvidence({ context });
    const links = linkEvidenceToMatrix(evidence, loadUseCaseMatrix({ context }));

    const matched = links.filter(
      (link) => link.useCaseId === USE_CASE_ID && link.resolution === "resolved" && link.semanticHash === "match"
    );
    const mismatched = links.filter(
      (link) => link.useCaseId === USE_CASE_ID && link.resolution === "resolved" && link.semanticHash === "mismatch"
    );
    const missing = links.filter((link) => link.useCaseId === "does.not.exist" && link.resolution === "missing");

    expect(matched).toHaveLength(1);
    expect(matched[0].sourcePath).toBe(resolved.useCase.source.path);
    expect(mismatched).toHaveLength(1);
    expect(missing).toHaveLength(1);
  });
});
