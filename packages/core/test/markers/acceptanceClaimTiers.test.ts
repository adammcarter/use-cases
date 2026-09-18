// What the acceptance claim rests on, said out loud.
//
// `proven: 285 of 297` was true and useless: it did not say that every one of
// those 285 came from the same forgeable file, that 42 of them were a unit-test
// filter declaring itself a `live_demo`, or that not one behaviour had been
// driven against the shipped product. A number nobody can decompose is a number
// nobody can check.
//
// The claim now counts each row at its STRONGEST tier and names the mix, and a
// performed run — a command the tool drove and recorded — counts alongside the
// local verifier run it used to ignore.
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

const SPAN = `sha256:${"a".repeat(64)}`;
const CONTEXT_HASH = `sha256:${"c".repeat(64)}`;
const GENERATED_AT = "2026-06-28T12:10:00Z";

function makeRow(rowId: string): FreshnessInputRow {
  return {
    row_id: rowId,
    intent: `behaviour ${rowId}`,
    verification_policy: { command: `npm test -- ${rowId}` },
    approval_policy: { mode: "none" }
  };
}

function makeBinding(rowId: string): CurrentBindingRecord {
  return {
    binding_slug: `${rowId}#handler`,
    row_id: rowId,
    suffix: "handler",
    file_path: `Sources/${rowId}.swift`,
    comment_prefix: "//",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v2",
    start_marker: { line: 12, column: 1 },
    end_marker: null,
    span: { start_line: 13, end_line: 27, start_byte: 355, end_byte: 849, sha256: SPAN },
    diagnostic: { symbol_kind: "swift_func", symbol_name: "handler", inferred: true }
  };
}

function makeRegistry(rowIds: string[]): MaterializedRegistry {
  const rowToSlugs = new Map<string, Set<string>>();
  const slugToRow = new Map<string, string>();
  for (const rowId of rowIds) {
    slugToRow.set(`${rowId}#handler`, rowId);
    rowToSlugs.set(rowId, new Set([`${rowId}#handler`]));
  }
  return { rowToSlugs, slugToRow };
}

function makeScan(bindings: CurrentBindingRecord[]): ScanResult {
  return { files: [], bindings, errors: [] };
}

function localResult(rowId: string, binding: CurrentBindingRecord): LocalVerificationResult {
  return {
    row_id: rowId,
    context_hash: CONTEXT_HASH,
    binding_set_hash: computeBindingSetHash(rowId, [
      {
        binding_slug: binding.binding_slug,
        row_id: binding.row_id,
        file_path: binding.file_path,
        extent_kind: binding.extent_kind,
        recognizer_id: binding.recognizer_id,
        span_canon_id: binding.span_canon_id,
        span_sha256: binding.span.sha256
      }
    ]),
    passed: true,
    attested: true
  };
}

function run(input: Partial<DeriveFreshnessInput> & { rows: FreshnessInputRow[] }) {
  const rowIds = input.rows.map((row) => row.row_id);
  const bindings = rowIds.map(makeBinding);
  return deriveFreshness({
    registry: makeRegistry(rowIds),
    scan: makeScan(bindings),
    evidence: [],
    policy_mode: "feature",
    generated_at: GENERATED_AT,
    product_root: "/workspace/product",
    current_context_hashes: new Map(rowIds.map((rowId) => [rowId, CONTEXT_HASH])),
    ...input
  });
}

describe("a performed run proves a row", () => {
  // The reversal of the measured experiment: genuine performed-run evidence used
  // to move the number by zero.
  test("a row with only a performed run is proven", () => {
    const row = makeRow("checkout.apply_coupon");
    const status = run({
      rows: [row],
      local_results: [],
      performed_runs: [{ row_id: row.row_id, argv: ["node", "dist/cli.js", "checkout"] }]
    });
    expect(status.rows[0].performed_run).toBe(true);
    expect(status.rows[0].local_status).toBe("UNVERIFIED_LOCAL");
    expect(status.acceptance_claim.proven).toBe(1);
    expect(status.acceptance_claim.claimable).toBe(true);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("a performed run for a row nobody bound still cannot prove it", () => {
    // An UNBOUND row has no code behind the claim at all; driving something and
    // naming the row does not supply one.
    const row = makeRow("checkout.orphan");
    const status = deriveFreshness({
      rows: [row],
      registry: makeRegistry([]),
      scan: makeScan([]),
      evidence: [],
      policy_mode: "feature",
      generated_at: GENERATED_AT,
      current_context_hashes: new Map(),
      local_results: [],
      performed_runs: [{ row_id: row.row_id, argv: ["node", "dist/cli.js"] }]
    });
    expect(status.rows[0].status).toBe("UNBOUND");
    expect(status.acceptance_claim.proven).toBe(0);
  });
});

describe("the claim names what it rests on", () => {
  test("each row is counted once, at its strongest tier", () => {
    const verified = makeRow("checkout.apply_coupon");
    const driven = makeRow("checkout.refund_order");
    const both = makeRow("checkout.void_order");
    const nothing = makeRow("checkout.reprice");
    const rows = [verified, driven, both, nothing];

    const status = run({
      rows,
      local_results: [
        localResult(verified.row_id, makeBinding(verified.row_id)),
        localResult(both.row_id, makeBinding(both.row_id))
      ],
      performed_runs: [
        { row_id: driven.row_id, argv: ["node", "dist/cli.js", "refund"] },
        { row_id: both.row_id, argv: ["node", "dist/cli.js", "void"] }
      ]
    });

    expect(status.acceptance_claim.proven).toBe(3);
    expect(status.acceptance_claim.total).toBe(4);
    // `both` is verified AND driven; it counts once, under the local run.
    expect(status.acceptance_claim.by_evidence).toEqual({
      signed_proof: 0,
      local_run: 2,
      performed_run: 1
    });
    expect(status.summary.performed_run).toBe(2);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("the basis carries the breakdown the statement cannot", () => {
    const verified = makeRow("checkout.apply_coupon");
    const driven = makeRow("checkout.refund_order");
    const status = run({
      rows: [verified, driven],
      local_results: [localResult(verified.row_id, makeBinding(verified.row_id))],
      performed_runs: [{ row_id: driven.row_id, argv: ["node", "dist/cli.js"] }]
    });
    expect(status.acceptance_claim.statement).toContain("SUPPORTED");
    // `statement` keeps its historic wording; `basis` is the sentence that says
    // what the number rests on.
    expect(status.acceptance_claim.basis).toBe(
      "0 signed proof, 1 local verifier run, 1 performed run"
    );
  });

  test("a matrix proven entirely by local verifier runs says so", () => {
    // The cowork-v2 shape: hundreds of rows, every one of them a spawned
    // verifier, not one behaviour driven. The claim must not read as if
    // something had been demonstrated.
    const rows = ["a", "b", "c"].map((suffix) => makeRow(`checkout.${suffix}`));
    const status = run({
      rows,
      local_results: rows.map((row) => localResult(row.row_id, makeBinding(row.row_id))),
      performed_runs: []
    });
    expect(status.acceptance_claim.basis).toBe(
      "0 signed proof, 3 local verifier run, 0 performed run"
    );
  });

  test("unattested rows are named in the statement, not silently dropped", () => {
    // The upgrade path: a repo whose whole ledger predates attestation must be
    // told what happened and what to run, not just handed a smaller number.
    const row = makeRow("checkout.apply_coupon");
    const status = run({
      rows: [row],
      local_results: [{ ...localResult(row.row_id, makeBinding(row.row_id)), attested: false }],
      performed_runs: []
    });
    expect(status.acceptance_claim.proven).toBe(0);
    expect(status.acceptance_claim.basis).toContain("1 unattested (run `use-cases verify`)");
  });

  test("omitting performed_runs entirely leaves existing callers unchanged", () => {
    const row = makeRow("checkout.apply_coupon");
    const status = run({
      rows: [row],
      local_results: [localResult(row.row_id, makeBinding(row.row_id))]
    });
    expect(status.rows[0].performed_run ?? false).toBe(false);
    expect(status.acceptance_claim.proven).toBe(1);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });
});
