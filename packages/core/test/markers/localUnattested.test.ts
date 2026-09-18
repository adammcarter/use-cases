// An unattested local result proves nothing.
//
// `VERIFIED_LOCAL` used to mean "a line exists in the results ledger whose
// hashes match". That rewarded the forgeable path: typing one line into
// `.use-cases/verification-results.jsonl` moved the acceptance claim, and
// nothing in the pipeline could tell that line from one a real run wrote.
//
// The keyless tier now requires a RUN ATTESTATION — proof the record was
// written by `use-cases verify`, which had to spawn the verifier to write it. A record
// without one reads UNATTESTED_LOCAL: visible, explained, and never counted as
// proven.
import { describe, expect, test } from "vitest";
import {
  computeBindingSetHash,
  deriveFreshness,
  validateFreshnessStatus,
  type CurrentBindingRecord,
  type DeriveFreshnessInput,
  type FreshnessInputRow,
  type LocalVerificationResult,
  type MaterializedRegistry,
  type ScanResult
} from "../../src/markers/index.js";

const SPAN_A = `sha256:${"a".repeat(64)}`;
const CONTEXT_HASH = `sha256:${"c".repeat(64)}`;
const GENERATED_AT = "2026-06-28T12:10:00Z";
const ROW_ID = "checkout.apply_coupon";
const SLUG = "checkout.apply_coupon#handler";

function makeRow(overrides: Partial<FreshnessInputRow> = {}): FreshnessInputRow {
  return {
    row_id: ROW_ID,
    intent: "apply a valid coupon to a cart",
    verification_policy: { command: "npm run test:usecase -- checkout.apply_coupon" },
    approval_policy: { required_for_release: true },
    ...overrides
  };
}

function makeBinding(slug: string): CurrentBindingRecord {
  const hashIndex = slug.indexOf("#");
  return {
    binding_slug: slug,
    row_id: hashIndex === -1 ? slug : slug.slice(0, hashIndex),
    suffix: hashIndex === -1 ? null : slug.slice(hashIndex + 1),
    file_path: "Sources/Checkout/CouponService.swift",
    comment_prefix: "//",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v2",
    start_marker: { line: 12, column: 1 },
    end_marker: null,
    span: { start_line: 13, end_line: 27, start_byte: 355, end_byte: 849, sha256: SPAN_A },
    diagnostic: { symbol_kind: "swift_func", symbol_name: "applyCoupon", inferred: true }
  };
}

function makeRegistry(pairs: Array<[string, string]>): MaterializedRegistry {
  const rowToSlugs = new Map<string, Set<string>>();
  const slugToRow = new Map<string, string>();
  for (const [rowId, slug] of pairs) {
    slugToRow.set(slug, rowId);
    const slugs = rowToSlugs.get(rowId) ?? new Set<string>();
    slugs.add(slug);
    rowToSlugs.set(rowId, slugs);
  }
  return { rowToSlugs, slugToRow };
}

function makeScan(bindings: CurrentBindingRecord[]): ScanResult {
  return { files: [], bindings, errors: [] };
}

function makeLocalResult(
  row: FreshnessInputRow,
  bindings: CurrentBindingRecord[],
  overrides: Partial<LocalVerificationResult> = {}
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
    context_hash: CONTEXT_HASH,
    binding_set_hash: computeBindingSetHash(row.row_id, items),
    passed: true,
    attested: true,
    ...overrides
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

function boundInput(row: FreshnessInputRow, results: LocalVerificationResult[]) {
  const binding = makeBinding(SLUG);
  return {
    rows: [row],
    registry: makeRegistry([[row.row_id, SLUG]]),
    scan: makeScan([binding]),
    current_context_hashes: new Map([[row.row_id, CONTEXT_HASH]]),
    local_results: results,
    binding
  };
}

describe("an unattested local result is not verification", () => {
  test("a hand-written result with perfect hashes reads UNATTESTED_LOCAL", () => {
    const row = makeRow();
    const { binding, ...input } = boundInput(row, []);
    const status = run({
      ...input,
      // Every hash matches the current state exactly — this is precisely the
      // forged line the old tier accepted. Only the attestation is missing.
      local_results: [makeLocalResult(row, [binding], { attested: false })]
    });
    const result = status.rows[0];
    expect(result.local_status).toBe("UNATTESTED_LOCAL");
    expect(result.local_reason).toMatch(/use-cases verify/);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("an unattested result never counts toward the acceptance claim", () => {
    const row = makeRow();
    const { binding, ...input } = boundInput(row, []);
    const status = run({
      ...input,
      local_results: [makeLocalResult(row, [binding], { attested: false })]
    });
    expect(status.acceptance_claim.proven).toBe(0);
    expect(status.acceptance_claim.claimable).toBe(false);
    expect(status.summary.verified_local).toBe(0);
    expect(status.summary.unattested_local).toBe(1);
  });

  test("the SAME result, attested, is VERIFIED_LOCAL and proven", () => {
    const row = makeRow();
    const { binding, ...input } = boundInput(row, []);
    const status = run({
      ...input,
      local_results: [makeLocalResult(row, [binding], { attested: true })]
    });
    expect(status.rows[0].local_status).toBe("VERIFIED_LOCAL");
    expect(status.acceptance_claim.proven).toBe(1);
    expect(status.summary.unattested_local).toBe(0);
  });

  test("one attested result rescues a row that also carries an unattested one", () => {
    // A forged line sitting next to an honest one must not poison the honest
    // one — the rule demotes records, it does not punish rows.
    const row = makeRow();
    const { binding, ...input } = boundInput(row, []);
    const status = run({
      ...input,
      local_results: [
        makeLocalResult(row, [binding], { attested: false }),
        makeLocalResult(row, [binding], { attested: true })
      ]
    });
    expect(status.rows[0].local_status).toBe("VERIFIED_LOCAL");
    expect(status.acceptance_claim.proven).toBe(1);
  });

  test("an unattested FAILING result still reads UNATTESTED_LOCAL, not STALE_LOCAL", () => {
    // Attestation is checked first: we cannot report anything about a run we
    // have no evidence happened, including that it failed.
    const row = makeRow();
    const { binding, ...input } = boundInput(row, []);
    const status = run({
      ...input,
      local_results: [makeLocalResult(row, [binding], { attested: false, passed: false })]
    });
    expect(status.rows[0].local_status).toBe("UNATTESTED_LOCAL");
  });

  test("a genuinely stale but attested result still reads STALE_LOCAL", () => {
    // The new rule must not swallow the existing drift signal.
    const row = makeRow();
    const { binding, ...input } = boundInput(row, []);
    const status = run({
      ...input,
      local_results: [
        makeLocalResult(row, [binding], { attested: true, context_hash: `sha256:${"d".repeat(64)}` })
      ]
    });
    expect(status.rows[0].local_status).toBe("STALE_LOCAL");
  });

  test("pure unit callers that omit `attested` are unaffected", () => {
    // Backward compatibility for callers that do not model attestation at all
    // (the field is undefined, not false). `scan` always sets it explicitly.
    const row = makeRow();
    const { binding, ...input } = boundInput(row, []);
    const result = makeLocalResult(row, [binding]);
    delete (result as { attested?: boolean }).attested;
    const status = run({ ...input, local_results: [result] });
    expect(status.rows[0].local_status).toBe("VERIFIED_LOCAL");
  });
});
