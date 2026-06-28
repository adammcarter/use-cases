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
  type MaterializedRegistry,
  type ProofEvent,
  type ScanResult
} from "../../src/markers/index.js";

// Deterministic span hashes for fixtures.
const SPAN_A = `sha256:${"a".repeat(64)}`;
const SPAN_B = `sha256:${"b".repeat(64)}`;

const GENERATED_AT = "2026-06-28T12:10:00Z";

// A loaded use-case row (the object `computeRowHash` hashes). The extra
// `intent` field stands in for the rest of the semantic row; editing it changes
// the row hash without touching the policies.
function makeRow(overrides: Partial<FreshnessInputRow> = {}): FreshnessInputRow {
  return {
    row_id: "checkout.apply_coupon",
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
    span_canon_id: "ucase-span-lines-v1",
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

// Build a proof event whose embedded hashes are derived from the supplied row +
// bindings, so it matches by default. Overrides simulate stale proofs.
function makeProof(
  row: FreshnessInputRow,
  bindings: CurrentBindingRecord[],
  overrides: {
    event_id?: string;
    created_at?: string;
    row_hash?: string;
    verification_policy_hash?: string;
    approval_policy_hash?: string;
    binding_set_hash?: string;
    result?: string;
    producer_kind?: string;
  } = {}
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
    event_id: overrides.event_id ?? "01JABCDEFAAAAAAAAAAAAAAAAAA",
    created_at: overrides.created_at ?? "2026-06-28T12:05:00Z",
    producer: {
      kind: overrides.producer_kind ?? "trusted-ci-prover",
      id: "github-actions/use-cases-prover",
      version: "0.1.0",
      ci_run_id: "123456789",
      repo: "org/product",
      commit: "0123456789abcdef0123456789abcdef01234567"
    },
    row: {
      row_id: row.row_id,
      row_hash_id: "existing-semantic-row-hash",
      row_hash: overrides.row_hash ?? computeRowHash(row),
      verification_policy_hash:
        overrides.verification_policy_hash ??
        computeVerificationPolicyHash(row.verification_policy),
      approval_policy_hash:
        overrides.approval_policy_hash ?? computeApprovalPolicyHash(row.approval_policy)
    },
    bindings: {
      binding_set_hash_id: "ucase-binding-set-v1",
      binding_set_hash:
        overrides.binding_set_hash ?? computeBindingSetHash(row.row_id, items),
      span_canon_id: "ucase-span-lines-v1",
      items
    },
    verification: {
      command_id: "acceptance.checkout.apply_coupon",
      result: overrides.result ?? "pass",
      started_at: "2026-06-28T12:04:10Z",
      completed_at: "2026-06-28T12:04:59Z",
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

describe("deriveFreshness", () => {
  test("acceptance 1: new row, no registry binding, no marker -> UNBOUND", () => {
    const row = makeRow();
    const status = run({ rows: [row] });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("UNBOUND");
    expect(status.summary.unbound).toBe(1);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 2: registered binding + current marker, no proof -> UNPROVEN", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([makeBinding(slug)])
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("UNPROVEN");
    expect(result.required_action).toBe("use-cases prove --row checkout.apply_coupon");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 3: proof matching row + binding set -> FRESH", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const binding = makeBinding(slug);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([binding]),
      evidence: [makeProof(row, [binding])]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("FRESH");
    expect(result.reasons).toEqual([]);
    expect(result.matching_proof_event?.event_id).toBe("01JABCDEFAAAAAAAAAAAAAAAAAA");
    expect(status.summary.fresh).toBe(1);
    expect(status.guard_ok).toBe(true);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 4: edit row after proof -> SUSPECT, ROW_HASH_CHANGED", () => {
    const provenRow = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const binding = makeBinding(slug);
    const proof = makeProof(provenRow, [binding]);
    const editedRow = makeRow({ intent: "apply a valid coupon to a cart (reworded)" });
    const status = run({
      rows: [editedRow],
      registry: makeRegistry([[editedRow.row_id, slug]]),
      scan: makeScan([binding]),
      evidence: [proof]
    });
    const result = rowOf(status, editedRow.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(result.reasons.map((reason) => reason.code)).toContain("ROW_HASH_CHANGED");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 5: edit marked span after proof -> SUSPECT, CODE_SPAN_CHANGED", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const provenBinding = makeBinding(slug, { span_sha256: SPAN_A });
    const proof = makeProof(row, [provenBinding]);
    const editedBinding = makeBinding(slug, { span_sha256: SPAN_B });
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([editedBinding]),
      evidence: [proof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    const codeChanged = result.reasons.find((reason) => reason.code === "CODE_SPAN_CHANGED");
    expect(codeChanged).toBeDefined();
    expect(codeChanged?.binding_slug).toBe(slug);
    expect(codeChanged?.expected_span_sha256).toBe(SPAN_A);
    expect(codeChanged?.actual_span_sha256).toBe(SPAN_B);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 6: marker removed while still registered -> SUSPECT, BINDING_REMOVED", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const proof = makeProof(row, [makeBinding(slug)]);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([]), // marker deleted from source
      evidence: [proof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(result.reasons.map((reason) => reason.code)).toContain("BINDING_REMOVED");
    expect(result.missing_registered_binding_slugs).toEqual([slug]);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 7: reprove after span edit (new proof matches new Hbind) -> FRESH", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const oldBinding = makeBinding(slug, { span_sha256: SPAN_A });
    const newBinding = makeBinding(slug, { span_sha256: SPAN_B });
    const oldProof = makeProof(row, [oldBinding], {
      event_id: "01JOLD0000000000000000000",
      created_at: "2026-06-28T12:05:00Z"
    });
    const newProof = makeProof(row, [newBinding], {
      event_id: "01JNEW0000000000000000000",
      created_at: "2026-06-28T13:00:00Z"
    });
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([newBinding]),
      evidence: [oldProof, newProof]
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("FRESH");
    expect(result.matching_proof_event?.event_id).toBe("01JNEW0000000000000000000");
    expect(result.latest_trusted_proof_event?.event_id).toBe("01JNEW0000000000000000000");
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 8: feature policy does not block a SUSPECT row", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const proof = makeProof(row, [makeBinding(slug, { span_sha256: SPAN_A })]);
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([makeBinding(slug, { span_sha256: SPAN_B })]),
      evidence: [proof],
      policy_mode: "feature"
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("SUSPECT");
    expect(result.policy_block).toBe(false);
    expect(status.summary.policy_blocked).toBe(0);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("acceptance 9: release policy blocks a required SUSPECT row, not a non-required one", () => {
    const requiredRow = makeRow({
      row_id: "checkout.apply_coupon",
      approval_policy: { required_for_release: true, trusted_producer: "trusted-ci-prover" }
    });
    const optionalRow = makeRow({
      row_id: "checkout.remove_coupon",
      approval_policy: { required_for_release: false, trusted_producer: "trusted-ci-prover" }
    });
    const reqSlug = "checkout.apply_coupon#handler";
    const optSlug = "checkout.remove_coupon#handler";
    const reqProof = makeProof(requiredRow, [makeBinding(reqSlug, { span_sha256: SPAN_A })]);
    const optProof = makeProof(optionalRow, [
      makeBinding(optSlug, { span_sha256: SPAN_A, file_path: "Sources/Checkout/Remove.swift" })
    ]);
    const status = run({
      rows: [requiredRow, optionalRow],
      registry: makeRegistry([
        [requiredRow.row_id, reqSlug],
        [optionalRow.row_id, optSlug]
      ]),
      scan: makeScan([
        makeBinding(reqSlug, { span_sha256: SPAN_B }),
        makeBinding(optSlug, { span_sha256: SPAN_B, file_path: "Sources/Checkout/Remove.swift" })
      ]),
      evidence: [reqProof, optProof],
      policy_mode: "release"
    });
    const required = rowOf(status, requiredRow.row_id);
    const optional = rowOf(status, optionalRow.row_id);
    expect(required.status).toBe("SUSPECT");
    expect(required.policy_block).toBe(true);
    expect(optional.status).toBe("SUSPECT");
    expect(optional.policy_block).toBe(false);
    expect(status.summary.policy_blocked).toBe(1);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("unregistered current marker -> INVALID, guard_ok false", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const status = run({
      rows: [row],
      registry: makeRegistry([]), // slug present in source but never registered
      scan: makeScan([makeBinding(slug)])
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("INVALID");
    expect(result.reasons.map((reason) => reason.code)).toContain("UNREGISTERED_BINDING");
    expect(result.unregistered_current_binding_slugs).toEqual([slug]);
    expect(status.guard_ok).toBe(false);
    expect(status.summary.invalid).toBe(1);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("INVALID is the first gate even when the marker is also stale (feature blocks INVALID)", () => {
    const row = makeRow();
    const status = run({
      rows: [row],
      registry: makeRegistry([]),
      scan: makeScan(
        [],
        [
          {
            code: "FORBIDDEN_MARKER_PAYLOAD" as never,
            message: "forbidden payload fresh=true",
            file_path: "Sources/Checkout/CouponService.swift",
            line: 12,
            slug: "checkout.apply_coupon#handler"
          }
        ]
      ),
      policy_mode: "feature"
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("INVALID");
    expect(result.policy_block).toBe(true);
    expect(status.guard_ok).toBe(false);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("custom policy predicate decides blocking", () => {
    const row = makeRow();
    const slug = "checkout.apply_coupon#handler";
    const status = run({
      rows: [row],
      registry: makeRegistry([[row.row_id, slug]]),
      scan: makeScan([makeBinding(slug)]),
      policy_mode: "custom",
      custom_policy: (ctx) => ctx.status !== "FRESH"
    });
    const result = rowOf(status, row.row_id);
    expect(result.status).toBe("UNPROVEN");
    expect(result.policy_block).toBe(true);
    expect(status.summary.policy_blocked).toBe(1);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });
});
