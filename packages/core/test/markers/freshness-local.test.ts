// Keyless VERIFIED_LOCAL freshness tier (Task 1, 0.1.0 keyless daily loop).
//
// `deriveFreshness` derives the headline `status` from *trusted signed* proofs.
// This suite exercises the parallel, keyless `local_status` field derived from
// the UNSIGNED verification-results ledger (the same records `verify --out`
// writes). A bound row with a passing unsigned result matching the row's current
// verification context + binding set reports `VERIFIED_LOCAL` — a green daily
// light with zero crypto — while `status` stays exactly what it was (UNPROVEN
// with no signed proof, FRESH with one). The signed-proof path is untouched.
import { describe, expect, test } from "vitest";
import {
  computeApprovalPolicyHash,
  computeBindingSetHash,
  computeRowHash,
  computeVerificationPolicyHash,
  deriveFreshness,
  validateFreshnessStatus,
  type CurrentBindingRecord,
  type DeriveFreshnessInput,
  type FreshnessInputRow,
  type LocalVerificationResult,
  type MaterializedRegistry,
  type ProofEvent,
  type ScanResult
} from "../../src/markers/index.js";

const SPAN_A = `sha256:${"a".repeat(64)}`;
const SPAN_B = `sha256:${"b".repeat(64)}`;
const CONTEXT_HASH = `sha256:${"c".repeat(64)}`;
const OTHER_CONTEXT_HASH = `sha256:${"d".repeat(64)}`;

const GENERATED_AT = "2026-06-28T12:10:00Z";
const ROW_ID = "checkout.apply_coupon";
const SLUG = "checkout.apply_coupon#handler";

function makeRow(overrides: Partial<FreshnessInputRow> = {}): FreshnessInputRow {
  return {
    row_id: ROW_ID,
    intent: "apply a valid coupon to a cart",
    verification_policy: { command: "npm run test:usecase -- checkout.apply_coupon" },
    approval_policy: { required_for_release: true, trusted_producer: "trusted-ci-prover" },
    ...overrides
  };
}

function makeBinding(
  slug: string,
  overrides: { file_path?: string; span_sha256?: string } = {}
): CurrentBindingRecord {
  const hashIndex = slug.indexOf("#");
  const rowId = hashIndex === -1 ? slug : slug.slice(0, hashIndex);
  const suffix = hashIndex === -1 ? null : slug.slice(hashIndex + 1);
  return {
    binding_slug: slug,
    row_id: rowId,
    suffix,
    file_path: overrides.file_path ?? "Sources/Checkout/CouponService.swift",
    comment_prefix: "//",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v2",
    start_marker: { line: 12, column: 1 },
    end_marker: null,
    span: {
      start_line: 13,
      end_line: 27,
      start_byte: 355,
      end_byte: 849,
      sha256: overrides.span_sha256 ?? SPAN_A
    },
    diagnostic: { symbol_kind: "swift_func", symbol_name: "applyCoupon", inferred: true }
  };
}

function makeRegistry(pairs: Array<[rowId: string, slug: string]>): MaterializedRegistry {
  const rowToSlugs = new Map<string, Set<string>>();
  const slugToRow = new Map<string, string>();
  for (const [rowId, slug] of pairs) {
    slugToRow.set(slug, rowId);
    let slugs = rowToSlugs.get(rowId);
    if (!slugs) {
      slugs = new Set<string>();
      rowToSlugs.set(rowId, slugs);
    }
    slugs.add(slug);
  }
  return { rowToSlugs, slugToRow };
}

function makeScan(bindings: CurrentBindingRecord[], errors: ScanResult["errors"] = []): ScanResult {
  return { files: [], bindings, errors };
}

// A passing unsigned verification result whose hashes are, by default, derived
// from the supplied row + bindings + context hash — so it matches the current
// state exactly. Overrides simulate drift.
function makeLocalResult(
  row: FreshnessInputRow,
  bindings: CurrentBindingRecord[],
  overrides: {
    context_hash?: string;
    binding_set_hash?: string;
    passed?: boolean;
  } = {}
): LocalVerificationResult {
  const items = bindings.map((binding) => ({
    binding_slug: binding.binding_slug,
    row_id: binding.row_id,
    file_path: binding.file_path,
    extent_kind: binding.extent_kind,
    recognizer_id: binding.recognizer_id,
    span_canon_id: binding.span_canon_id,
    span_sha256: binding.span.sha256
  }));
  return {
    row_id: row.row_id,
    context_hash: overrides.context_hash ?? CONTEXT_HASH,
    binding_set_hash: overrides.binding_set_hash ?? computeBindingSetHash(row.row_id, items),
    passed: overrides.passed ?? true
  };
}

// A signed proof event that matches the current row + binding set + context by
// default (mirrors freshness.test.ts's makeProof).
function makeProof(
  row: FreshnessInputRow,
  bindings: CurrentBindingRecord[]
): ProofEvent {
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
      span_canon_id: "ucase-span-lines-v2",
      items
    },
    verification: {
      command_id: "acceptance.checkout.apply_coupon",
      result: "pass",
      started_at: "2026-06-28T12:04:10Z",
      completed_at: "2026-06-28T12:04:59Z",
      context_hash: CONTEXT_HASH,
      artifacts: []
    },
    signature: { alg: "ed25519", key_id: "trusted-ci-2026-01", value: "base64" }
  };
}

function run(input: Partial<DeriveFreshnessInput> & { rows: FreshnessInputRow[] }) {
  return deriveFreshness({
    registry: makeRegistry([]),
    scan: makeScan([]),
    evidence: [],
    policy_mode: "feature",
    generated_at: GENERATED_AT,
    product_root: "/workspace/product",
    ...input
  });
}

function rowOf(status: ReturnType<typeof deriveFreshness>, rowId: string) {
  const row = status.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} not found in status`);
  }
  return row;
}

describe("deriveFreshness local_status", () => {
  test("bound + locally verified, unsigned => VERIFIED_LOCAL with status still UNPROVEN", () => {
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      evidence: [],
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: [makeLocalResult(row, [binding])]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("UNPROVEN");
    expect(result.local_status).toBe("VERIFIED_LOCAL");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("bound but no local result yet => UNVERIFIED_LOCAL", () => {
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: []
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("UNPROVEN");
    expect(result.local_status).toBe("UNVERIFIED_LOCAL");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("local result exists but the context hash drifted => STALE_LOCAL", () => {
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      // The unsigned result was recorded against a now-stale verifier context.
      local_results: [makeLocalResult(row, [binding], { context_hash: OTHER_CONTEXT_HASH })]
    });
    const result = rowOf(status, row.row_id);
    expect(result.local_status).toBe("STALE_LOCAL");
    expect(result.local_reason).toBeDefined();
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("local result exists but the code span drifted (hBind changed) => STALE_LOCAL", () => {
    const row = makeRow();
    const oldBinding = makeBinding(SLUG, { span_sha256: SPAN_A });
    const newBinding = makeBinding(SLUG, { span_sha256: SPAN_B });
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([newBinding]), // code changed since the result was recorded
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: [makeLocalResult(row, [oldBinding])]
    });
    const result = rowOf(status, row.row_id);
    expect(result.local_status).toBe("STALE_LOCAL");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("a failing local result never reports VERIFIED_LOCAL => STALE_LOCAL", () => {
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: [makeLocalResult(row, [binding], { passed: false })]
    });
    const result = rowOf(status, row.row_id);
    expect(result.local_status).toBe("STALE_LOCAL");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("UNBOUND row has no local_status", () => {
    const row = makeRow();
    const status = run({
      rows: [row],
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: []
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("UNBOUND");
    expect(result.local_status ?? null).toBeNull();
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("FRESH precedence: signed FRESH row reports VERIFIED_LOCAL even with NO local result", () => {
    // The unsigned ledger is opted-in but empty for this row (the common case:
    // the proof was minted in CI and `verify --out` never wrote a local result
    // here). FRESH must still show the green daily light. Without the FRESH
    // override this would be UNVERIFIED_LOCAL, so this test is discriminating.
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      evidence: [makeProof(row, [binding])],
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: []
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("FRESH");
    expect(result.local_status).toBe("VERIFIED_LOCAL");
    expect(result.local_reason).toBe("backed by trusted signed proof");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("FRESH precedence: signed FRESH row reports VERIFIED_LOCAL even with a STALE local result", () => {
    // A trusted signed proof outranks a stale/failed unsigned run. Without the
    // FRESH override this row would be STALE_LOCAL, so this too is discriminating.
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      evidence: [makeProof(row, [binding])],
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: [makeLocalResult(row, [binding], { context_hash: OTHER_CONTEXT_HASH })]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("FRESH");
    expect(result.local_status).toBe("VERIFIED_LOCAL");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("backward compatible: no local_results input => local_status absent", () => {
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding])
      // no current_context_hashes, no local_results
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("UNPROVEN");
    expect(result.local_status ?? null).toBeNull();
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// The summary carried only the SIGNED axis (fresh/suspect/unproven/unbound), so
// a fully-green keyless matrix still read `fresh: 0, unproven: N` — the local
// axis it actually gates on day to day was invisible, and agents "fixed" rows
// that were never broken. Counts for the local axis are additive; nothing that
// already existed moves or changes meaning.
// ---------------------------------------------------------------------------
describe("summary carries the local axis", () => {
  test("counts verified_local / stale_local / unverified_local alongside the signed axis", () => {
    const rowA = makeRow({ row_id: "checkout.apply_coupon" });
    const rowB = makeRow({ row_id: "checkout.refund_order" });
    const rowC = makeRow({ row_id: "checkout.void_order" });
    const slugA = "checkout.apply_coupon#handler";
    const slugB = "checkout.refund_order#handler";
    const slugC = "checkout.void_order#handler";
    const bindA = makeBinding(slugA);
    const bindB = makeBinding(slugB);
    const bindC = makeBinding(slugC);

    const status = run({
      rows: [rowA, rowB, rowC],
      registry: makeRegistry([
        [rowA.row_id, slugA],
        [rowB.row_id, slugB],
        [rowC.row_id, slugC]
      ]),
      scan: makeScan([bindA, bindB, bindC]),
      current_context_hashes: new Map([
        [rowA.row_id, CONTEXT_HASH],
        [rowB.row_id, CONTEXT_HASH],
        [rowC.row_id, CONTEXT_HASH]
      ]),
      local_results: [
        // A: current -> VERIFIED_LOCAL. B: context drifted -> STALE_LOCAL.
        // C: no result at all -> UNVERIFIED_LOCAL.
        makeLocalResult(rowA, [bindA]),
        makeLocalResult(rowB, [bindB], { context_hash: OTHER_CONTEXT_HASH })
      ]
    });

    expect(status.summary.verified_local).toBe(1);
    expect(status.summary.stale_local).toBe(1);
    expect(status.summary.unverified_local).toBe(1);
    // The signed axis is untouched: no proofs, so every row is still UNPROVEN.
    expect(status.summary.fresh).toBe(0);
    expect(status.summary.unproven).toBe(3);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// `guard_ok` answers "is any policy blocking?", NOT "is anything proven?" — so it
// reads `true` on a matrix where zero rows are verified. Two independent field
// reports record agents nearly claiming acceptance off that green boolean.
// `guard_ok` KEEPS its meaning (existing gates must not flip); we add a field
// that states the acceptance conclusion outright, so an agent has a true thing
// to quote.
// ---------------------------------------------------------------------------
describe("acceptance_claim states the conclusion guard_ok does not", () => {
  test("nothing proven => claimable false, even though guard_ok is true", () => {
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: []
    });

    // The pre-existing gate is unchanged — nothing is INVALID, so it stays green.
    expect(status.guard_ok).toBe(true);
    // …but the acceptance conclusion is the honest one.
    expect(status.acceptance_claim.proven).toBe(0);
    expect(status.acceptance_claim.total).toBe(1);
    expect(status.acceptance_claim.claimable).toBe(false);
    expect(status.acceptance_claim.statement).toContain("NOT_SUPPORTED");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("every row locally verified => claimable true with no signed proof", () => {
    const row = makeRow();
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, SLUG]]),
      scan: makeScan([binding]),
      current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
      local_results: [makeLocalResult(row, [binding])]
    });

    expect(status.acceptance_claim.proven).toBe(1);
    expect(status.acceptance_claim.total).toBe(1);
    expect(status.acceptance_claim.claimable).toBe(true);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("an UNBOUND row is never proven, so it blocks the claim", () => {
    const bound = makeRow({ row_id: "checkout.apply_coupon" });
    const unbound = makeRow({ row_id: "checkout.orphan" });
    const binding = makeBinding(SLUG);
    const status = run({
      rows: [bound, unbound],
      registry: makeRegistry([[bound.row_id, SLUG]]),
      scan: makeScan([binding]),
      current_context_hashes: new Map([[bound.row_id, CONTEXT_HASH]]),
      local_results: [makeLocalResult(bound, [binding])]
    });

    expect(status.summary.unbound).toBe(1);
    expect(status.acceptance_claim.proven).toBe(1);
    expect(status.acceptance_claim.total).toBe(2);
    expect(status.acceptance_claim.claimable).toBe(false);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });
});
