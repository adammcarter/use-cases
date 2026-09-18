// Run attestation: the keyless tier's answer to "was this line WRITTEN BY A RUN,
// or typed?"
//
// The unsigned verification-results ledger is a plain JSONL file. Before this,
// `scan` trusted any line in it whose hashes matched — so appending one
// hand-written line moved the acceptance claim, while genuinely driving the
// product moved nothing. A machine-local HMAC over each record closes that: only
// `use-cases verify`, which actually spawned the verifier, holds the key, so a typed
// line carries no valid attestation and proves nothing.
//
// This is NOT the signing tier: the key is auto-minted on first use, lives
// outside the repo, and needs no CI, no keyring, and no user action.
import { describe, expect, test } from "vitest";
import {
  computeRunAttestation,
  resolveLocalRunKey,
  verifyRunAttestation,
  type MarkerFs
} from "../../src/markers/index.js";

const KEY = "a".repeat(64);
const OTHER_KEY = "b".repeat(64);

function makeRecord(overrides: Record<string, unknown> = {}) {
  return {
    schema: "ucase-verification-result-v1",
    row_id: "checkout.apply_coupon",
    slug: "checkout.apply_coupon",
    status: "pass",
    evidence_kind: "test_result",
    verifier_id: "acceptance",
    verifier_kind: "script",
    exit_code: 0,
    row_hash: `sha256:${"1".repeat(64)}`,
    binding_set_hash: `sha256:${"2".repeat(64)}`,
    span_sha256s: [`sha256:${"3".repeat(64)}`],
    verification_context_hash: `sha256:${"4".repeat(64)}`,
    stdout_sha256: `sha256:${"5".repeat(64)}`,
    stderr_sha256: `sha256:${"6".repeat(64)}`,
    created_at: "2026-06-28T12:10:00.000Z",
    ...overrides
  };
}

// An in-memory MarkerFs so key minting never touches the real home directory.
function memoryFs(seed: Record<string, string> = {}): MarkerFs {
  const files = new Map(Object.entries(seed));
  return {
    readText: (path: string) => files.get(path) ?? null,
    writeText: (path: string, text: string) => {
      files.set(path, text);
    },
    exists: (path: string) => files.has(path),
    listDir: () => []
  };
}

describe("computeRunAttestation", () => {
  test("a record attested with a key verifies against that key", () => {
    const record = makeRecord();
    const attested = { ...record, run_attestation: computeRunAttestation(record, KEY) };
    expect(verifyRunAttestation(attested, KEY)).toBe(true);
  });

  test("the attestation names its algorithm so a reader can tell what it is", () => {
    expect(computeRunAttestation(makeRecord(), KEY)).toMatch(/^hmac-sha256:[0-9a-f]{64}$/);
  });

  // THE defect, at unit scale: edit any field of an attested record and the
  // attestation must stop verifying. Without this, an attacker flips `status`
  // from fail to pass and keeps the stolen attestation.
  test("editing ANY field of an attested record breaks the attestation", () => {
    const record = makeRecord();
    const attestation = computeRunAttestation(record, KEY);
    for (const field of [
      "row_id",
      "status",
      "exit_code",
      "binding_set_hash",
      "verification_context_hash",
      "created_at"
    ]) {
      const tampered = {
        ...record,
        [field]: field === "exit_code" ? 7 : `tampered-${field}`,
        run_attestation: attestation
      };
      expect(verifyRunAttestation(tampered, KEY)).toBe(false);
    }
  });

  test("a record with no attestation at all never verifies", () => {
    expect(verifyRunAttestation(makeRecord(), KEY)).toBe(false);
  });

  test("an attestation minted with a different key does not verify", () => {
    const record = makeRecord();
    const attested = { ...record, run_attestation: computeRunAttestation(record, OTHER_KEY) };
    expect(verifyRunAttestation(attested, KEY)).toBe(false);
  });

  test("with no key resolvable, nothing verifies (fail closed)", () => {
    const record = makeRecord();
    const attested = { ...record, run_attestation: computeRunAttestation(record, KEY) };
    expect(verifyRunAttestation(attested, null)).toBe(false);
  });

  // Field ORDER in the JSON must not change the attestation: the ledger is
  // rewritten by every merge, and a reordering merge must not invalidate an
  // honest record.
  test("the attestation is independent of key order in the record", () => {
    const record = makeRecord();
    const reordered = Object.fromEntries(Object.entries(record).reverse());
    expect(computeRunAttestation(reordered, KEY)).toBe(computeRunAttestation(record, KEY));
  });
});

describe("resolveLocalRunKey", () => {
  test("mints a key on first use and reuses it after", () => {
    const fs = memoryFs();
    const first = resolveLocalRunKey("/home/tester/.use-cases/run-key", fs);
    expect(first).toMatch(/^[0-9a-f]{64}$/);
    const second = resolveLocalRunKey("/home/tester/.use-cases/run-key", fs);
    expect(second).toBe(first);
  });

  test("a different machine (a different key file) gets a different key", () => {
    const a = resolveLocalRunKey("/home/a/.use-cases/run-key", memoryFs());
    const b = resolveLocalRunKey("/home/b/.use-cases/run-key", memoryFs());
    expect(a).not.toBe(b);
  });

  test("a corrupt key file is replaced rather than crashing the run", () => {
    const fs = memoryFs({ "/home/tester/.use-cases/run-key": "not-a-key\n" });
    expect(resolveLocalRunKey("/home/tester/.use-cases/run-key", fs)).toMatch(/^[0-9a-f]{64}$/);
  });
});
