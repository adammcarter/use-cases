import { generateKeyPairSync } from "node:crypto";
import { describe, expect, test } from "vitest";
import {
  VERIFICATION_CONTEXT_HASH_ID,
  computeBindingSetHash,
  computeApprovalPolicyHash,
  computeRowHash,
  computeVerificationContextHash,
  computeRowVerificationContextHash,
  computeVerificationPolicyHash,
  deriveFreshness,
  proofSigningPayload,
  resolveRowVerifiers,
  signEvent,
  singleKeyResolver,
  verifyEvent,
  type CurrentBindingRecord,
  type FreshnessInputRow,
  type MaterializedRegistry,
  type ProofEvent,
  type ScanResult
} from "../../src/markers/index.js";

const ROW_ID = "checkout.apply_coupon";
const SLUG = `${ROW_ID}#handler`;
const ROOT = "/repo";
const GENERATED_AT = "2026-06-28T12:10:00Z";
const HASH_RE = /^sha256:[0-9a-f]{64}$/;

// The `acceptance` verifier is declared as the `js.vitest` preset, which resolves
// its input to `tests/use-cases/<slug>.test.ts`; here the slug is the row id.
const ACCEPTANCE_INPUT = `${ROOT}/tests/use-cases/${ROW_ID}.test.ts`;
const LOCKFILE = `${ROOT}/pnpm-lock.yaml`;

const VERIFICATION_POLICY = {
  mode: "requirements",
  verifiers: {
    acceptance: { preset: "js.vitest" }
  },
  requirements: [
    { evidence_kind: "test_result", required_verifiers: ["acceptance"], minimum_count: 1 }
  ]
};

// A minimal injectable read-only fs over an in-memory absolute-path map.
function fakeFs(files: Record<string, string>) {
  return { readText: (path: string): string | null => (path in files ? files[path] : null) };
}

function makeRow(): FreshnessInputRow {
  return {
    row_id: ROW_ID,
    intent: "apply a valid coupon to a cart",
    verification_policy: VERIFICATION_POLICY,
    approval_policy: { mode: "none" }
  };
}

function makeBinding(): CurrentBindingRecord {
  return {
    binding_slug: SLUG,
    row_id: ROW_ID,
    suffix: "handler",
    file_path: "Sources/Checkout/CouponService.swift",
    comment_prefix: "//",
    extent_kind: "explicit",
    recognizer_id: "explicit-span-v1",
    span_canon_id: "ucase-span-lines-v1",
    start_marker: { line: 12, column: 1 },
    end_marker: { line: 20, column: 1 },
    span: {
      start_line: 13,
      end_line: 19,
      start_byte: 355,
      end_byte: 849,
      sha256: `sha256:${"a".repeat(64)}`
    },
    diagnostic: { symbol_kind: "explicit", symbol_name: "applyCoupon", inferred: false }
  };
}

function makeRegistry(): MaterializedRegistry {
  return {
    rowToSlugs: new Map([[ROW_ID, new Set([SLUG])]]),
    slugToRow: new Map([[SLUG, ROW_ID]])
  };
}

function makeScan(bindings: CurrentBindingRecord[]): ScanResult {
  return { files: [], bindings, errors: [] };
}

function makeProof(row: FreshnessInputRow, bindings: CurrentBindingRecord[], contextHash: string): ProofEvent {
  const items = bindings.map((binding) => ({
    binding_slug: binding.binding_slug,
    row_id: binding.row_id,
    file_path: binding.file_path,
    extent_kind: binding.extent_kind,
    recognizer_id: binding.recognizer_id,
    span_canon_id: binding.span_canon_id,
    span_sha256: binding.span.sha256,
    span_start_line: binding.span.start_line,
    span_end_line: binding.span.end_line
  }));
  return {
    schema: "ucase-proof-event-v1",
    event_type: "row_proof_passed",
    event_id: "01JABCDEFAAAAAAAAAAAAAAAAAA",
    created_at: "2026-06-28T12:05:00Z",
    producer: {
      kind: "trusted-ci-prover",
      id: "github-actions/use-cases-prover",
      version: "0.1.0",
      ci_run_id: "123456789",
      repo: "org/product",
      commit: "0123456789abcdef0123456789abcdef01234567"
    },
    row: {
      row_id: row.row_id,
      row_hash_id: "existing-semantic-row-hash",
      row_hash: computeRowHash(row),
      verification_policy_hash: computeVerificationPolicyHash(row.verification_policy),
      approval_policy_hash: computeApprovalPolicyHash(row.approval_policy)
    },
    bindings: {
      binding_set_hash_id: "ucase-binding-set-v1",
      binding_set_hash: computeBindingSetHash(row.row_id, items),
      span_canon_id: "ucase-span-lines-v1",
      items
    },
    verification: {
      command_id: "acceptance.checkout.apply_coupon",
      result: "pass",
      started_at: "2026-06-28T12:04:10Z",
      completed_at: "2026-06-28T12:04:59Z",
      artifacts: [],
      context_hash_id: VERIFICATION_CONTEXT_HASH_ID,
      context_hash: contextHash
    }
  };
}

describe("computeVerificationContextHash", () => {
  test("returns a stable sha256 over policy, resolved verifier, declared inputs, and lockfile", () => {
    const fs = fakeFs({ [ACCEPTANCE_INPUT]: "the acceptance test", [LOCKFILE]: "lock-1" });
    const verifiers = resolveRowVerifiers({ slug: ROW_ID, verification_policy: VERIFICATION_POLICY });
    const hash = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs
    });
    expect(hash).toMatch(HASH_RE);
    // Deterministic: recomputing over the same inputs gives the same hash.
    expect(
      computeVerificationContextHash({ verificationPolicy: VERIFICATION_POLICY, verifiers, rootDir: ROOT, fs })
    ).toBe(hash);
  });

  test("is independent of unrelated files (only declared inputs + lockfile matter)", () => {
    const verifiers = resolveRowVerifiers({ slug: ROW_ID, verification_policy: VERIFICATION_POLICY });
    const base = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "T", [LOCKFILE]: "L" })
    });
    const withNoise = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "T", [LOCKFILE]: "L", [`${ROOT}/unrelated/file.ts`]: "noise" })
    });
    expect(withNoise).toBe(base);
  });

  test("changing a declared input's contents changes the hash (weakening the acceptance test)", () => {
    const verifiers = resolveRowVerifiers({ slug: ROW_ID, verification_policy: VERIFICATION_POLICY });
    const original = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "strict test", [LOCKFILE]: "L" })
    });
    const weakened = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "weak test", [LOCKFILE]: "L" })
    });
    expect(weakened).not.toBe(original);
  });

  test("changing the lockfile changes the hash", () => {
    const verifiers = resolveRowVerifiers({ slug: ROW_ID, verification_policy: VERIFICATION_POLICY });
    const a = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "T", [LOCKFILE]: "lock-a" })
    });
    const b = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "T", [LOCKFILE]: "lock-b" })
    });
    expect(b).not.toBe(a);
  });

  test("a missing input file is handled deterministically (absent marker, no throw)", () => {
    const verifiers = resolveRowVerifiers({ slug: ROW_ID, verification_policy: VERIFICATION_POLICY });
    const compute = () =>
      computeVerificationContextHash({
        verificationPolicy: VERIFICATION_POLICY,
        verifiers,
        rootDir: ROOT,
        fs: fakeFs({ [LOCKFILE]: "L" }) // acceptance input file is absent
      });
    expect(compute).not.toThrow();
    expect(compute()).toBe(compute());
    // Deleting the input (absent) must differ from a present-but-empty input.
    const present = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "", [LOCKFILE]: "L" })
    });
    expect(present).not.toBe(compute());
  });

  test("computeRowVerificationContextHash resolves the row's verifiers then hashes", () => {
    const fs = fakeFs({ [ACCEPTANCE_INPUT]: "T", [LOCKFILE]: "L" });
    const viaRow = computeRowVerificationContextHash({
      slug: ROW_ID,
      verificationPolicy: VERIFICATION_POLICY,
      rootDir: ROOT,
      fs
    });
    const verifiers = resolveRowVerifiers({ slug: ROW_ID, verification_policy: VERIFICATION_POLICY });
    const viaLow = computeVerificationContextHash({
      verificationPolicy: VERIFICATION_POLICY,
      verifiers,
      rootDir: ROOT,
      fs
    });
    expect(viaRow).toBe(viaLow);
  });
});

describe("verification context hash in the signed proof payload", () => {
  test("the context hash is inside canonicalJson(event-without-signature), so it is signed", () => {
    const { publicKey, privateKey } = generateKeyPairSync("ed25519");
    const row = makeRow();
    const contextHash = computeRowVerificationContextHash({
      slug: ROW_ID,
      verificationPolicy: VERIFICATION_POLICY,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "T", [LOCKFILE]: "L" })
    });
    const unsigned = makeProof(row, [makeBinding()], contextHash);
    const signed = signEvent(
      unsigned as unknown as Record<string, unknown>,
      privateKey,
      "trusted-ci"
    );
    // The signing payload must carry the context hash (so tampering breaks the sig).
    expect(proofSigningPayload(signed)).toContain(contextHash);
    // And the signature verifies over exactly that payload.
    expect(verifyEvent(signed as Record<string, unknown>, singleKeyResolver(publicKey)).ok).toBe(true);
  });
});

describe("deriveFreshness binds proofs to the verification context", () => {
  function run(contextHash: string, recomputed: string) {
    const row = makeRow();
    const binding = makeBinding();
    const proof = makeProof(row, [binding], contextHash);
    return deriveFreshness({
      rows: [row],
      registry: makeRegistry(),
      scan: makeScan([binding]),
      evidence: [proof],
      policy_mode: "feature",
      generated_at: GENERATED_AT,
      product_root: ROOT,
      current_context_hashes: new Map([[ROW_ID, recomputed]])
    });
  }

  test("a proof whose context hash matches the freshly recomputed one => FRESH", () => {
    const fs = fakeFs({ [ACCEPTANCE_INPUT]: "strict test", [LOCKFILE]: "L" });
    const ctx = computeRowVerificationContextHash({
      slug: ROW_ID,
      verificationPolicy: VERIFICATION_POLICY,
      rootDir: ROOT,
      fs
    });
    const status = run(ctx, ctx);
    const rowOut = status.rows.find((entry) => entry.row_id === ROW_ID);
    expect(rowOut?.status).toBe("FRESH");
  });

  test("weakening a declared input changes the recomputed context hash => NOT FRESH", () => {
    const ctxOriginal = computeRowVerificationContextHash({
      slug: ROW_ID,
      verificationPolicy: VERIFICATION_POLICY,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "strict test", [LOCKFILE]: "L" })
    });
    const ctxWeakened = computeRowVerificationContextHash({
      slug: ROW_ID,
      verificationPolicy: VERIFICATION_POLICY,
      rootDir: ROOT,
      fs: fakeFs({ [ACCEPTANCE_INPUT]: "weak test", [LOCKFILE]: "L" })
    });
    expect(ctxWeakened).not.toBe(ctxOriginal);
    // Proof was minted against the ORIGINAL context; current recompute is WEAKENED.
    const status = run(ctxOriginal, ctxWeakened);
    const rowOut = status.rows.find((entry) => entry.row_id === ROW_ID);
    expect(rowOut?.status).toBe("SUSPECT");
    expect(rowOut?.reasons.some((reason) => reason.code === "VERIFICATION_CONTEXT_CHANGED")).toBe(true);
  });
});
