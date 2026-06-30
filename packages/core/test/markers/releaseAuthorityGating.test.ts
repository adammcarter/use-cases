// Release-gate AUTHORITY requirement (public-v1, Phase 2, Piece 2).
//
// A repo may require a MINIMUM provenance authority for required_for_release
// rows: `release_gate.required_authority: "ci"` (the matching proof's
// authority.type must be "ci") and/or `release_gate.require_protected_ref: true`
// (authority.protected_ref must be true). A required row whose only FRESH proof
// was minted with insufficient authority is POLICY-BLOCKED in release mode and
// surfaced with an AUTHORITY_INSUFFICIENT reason. The gate is OPTIONAL/off by
// default (nothing changes when it is not configured) and feature mode is never
// affected. The new block is ADDITIVE: it only ever blocks an otherwise-FRESH
// required row; it never relaxes the existing not-FRESH blocking.
import { describe, expect, test } from "vitest";
import {
  computeApprovalPolicyHash,
  computeBindingSetHash,
  computeRowHash,
  computeVerificationPolicyHash,
  deriveFreshness,
  validateFreshnessStatus,
  type CiAuthority,
  type CurrentBindingRecord,
  type DeriveFreshnessInput,
  type FreshnessInputRow,
  type MaterializedRegistry,
  type ProofEvent,
  type ReleaseGatePolicy,
  type ScanResult
} from "../../src/markers/index.js";

const SPAN_A = `sha256:${"a".repeat(64)}`;
const GENERATED_AT = "2026-06-28T12:10:00Z";

function makeRow(overrides: Partial<FreshnessInputRow> = {}): FreshnessInputRow {
  return {
    row_id: "checkout.apply_coupon",
    intent: "apply a valid coupon to a cart",
    verification_policy: { command: "npm run test:usecase -- checkout.apply_coupon" },
    approval_policy: { required_for_release: true, trusted_producer: "trusted-ci-prover" },
    ...overrides
  };
}

function makeBinding(slug: string): CurrentBindingRecord {
  const hashIndex = slug.indexOf("#");
  const rowId = hashIndex === -1 ? slug : slug.slice(0, hashIndex);
  const suffix = hashIndex === -1 ? null : slug.slice(hashIndex + 1);
  return {
    binding_slug: slug,
    row_id: rowId,
    suffix,
    file_path: "Sources/Checkout/CouponService.swift",
    comment_prefix: "//",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v1",
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
    let slugs = rowToSlugs.get(rowId);
    if (!slugs) {
      slugs = new Set<string>();
      rowToSlugs.set(rowId, slugs);
    }
    slugs.add(slug);
  }
  return { rowToSlugs, slugToRow };
}

function makeScan(bindings: CurrentBindingRecord[]): ScanResult {
  return { files: [], bindings, errors: [] };
}

// A FRESH-matching proof with an OPTIONAL embedded authority block.
function makeProof(
  row: FreshnessInputRow,
  bindings: CurrentBindingRecord[],
  authority?: CiAuthority
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
  const event: ProofEvent = {
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
      artifacts: []
    },
    signature: { alg: "ed25519", key_id: "trusted-ci-2026-01", value: "base64" }
  };
  if (authority) {
    event.authority = authority;
  }
  return event;
}

const CI_PROTECTED: CiAuthority = {
  type: "ci",
  provider: "github-actions",
  repository: "org/product",
  protected_ref: true
};
const CI_UNKNOWN_PROTECTION: CiAuthority = {
  type: "ci",
  provider: "github-actions",
  repository: "org/product",
  protected_ref: null
};
const LOCAL_AUTHORITY: CiAuthority = { type: "local", provider: "generic" };

function freshRequiredRow(
  authority: CiAuthority | undefined,
  releaseGate: ReleaseGatePolicy | undefined,
  mode: "feature" | "release" = "release",
  approvalOverride?: Record<string, unknown>
) {
  const row = makeRow(
    approvalOverride ? { approval_policy: approvalOverride } : {}
  );
  const slug = "checkout.apply_coupon#handler";
  const binding = makeBinding(slug);
  const input: Partial<DeriveFreshnessInput> & { rows: FreshnessInputRow[] } = {
    rows: [row],
    registry: makeRegistry([[row.row_id, slug]]),
    scan: makeScan([binding]),
    evidence: [makeProof(row, [binding], authority)],
    policy_mode: mode,
    release_gate: releaseGate
  };
  const status = deriveFreshness({
    generated_at: GENERATED_AT,
    product_root: "/workspace/product",
    ...input
  });
  const out = status.rows.find((r) => r.row_id === row.row_id);
  if (!out) {
    throw new Error("row not found");
  }
  return { status, row: out };
}

describe("release-gate authority requirement", () => {
  test("required_authority:'ci' PASSES a row whose FRESH proof has type:'ci'", () => {
    const { status, row } = freshRequiredRow(CI_PROTECTED, { required_authority: "ci" });
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(false);
    expect(status.summary.policy_blocked).toBe(0);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("required_authority:'ci' BLOCKS a row whose FRESH proof has type:'local'", () => {
    const { status, row } = freshRequiredRow(LOCAL_AUTHORITY, { required_authority: "ci" });
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(true);
    expect(row.reasons.map((r) => r.code)).toContain("AUTHORITY_INSUFFICIENT");
    expect(status.summary.policy_blocked).toBe(1);
    expect(validateFreshnessStatus(status).ok).toBe(true);
  });

  test("required_authority:'ci' BLOCKS a row whose FRESH proof has NO authority block", () => {
    const { row } = freshRequiredRow(undefined, { required_authority: "ci" });
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(true);
    expect(row.reasons.map((r) => r.code)).toContain("AUTHORITY_INSUFFICIENT");
  });

  test("require_protected_ref BLOCKS a proof whose protected_ref is not true", () => {
    const { row } = freshRequiredRow(CI_UNKNOWN_PROTECTION, {
      required_authority: "ci",
      require_protected_ref: true
    });
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(true);
    expect(row.reasons.map((r) => r.code)).toContain("AUTHORITY_INSUFFICIENT");
  });

  test("require_protected_ref PASSES a proof whose protected_ref is true", () => {
    const { row } = freshRequiredRow(CI_PROTECTED, {
      required_authority: "ci",
      require_protected_ref: true
    });
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(false);
  });

  test("with NO authority gate configured, a type:'local' FRESH proof is NOT blocked (as today)", () => {
    const { status, row } = freshRequiredRow(LOCAL_AUTHORITY, undefined);
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(false);
    expect(status.summary.policy_blocked).toBe(0);
  });

  test("an EMPTY authority gate ({}) changes nothing", () => {
    const { row } = freshRequiredRow(LOCAL_AUTHORITY, {});
    expect(row.policy_block).toBe(false);
  });

  test("feature mode is unaffected by the authority gate", () => {
    const { row } = freshRequiredRow(LOCAL_AUTHORITY, { required_authority: "ci" }, "feature");
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(false);
  });

  test("a NON-required FRESH row is never authority-blocked", () => {
    const { row } = freshRequiredRow(LOCAL_AUTHORITY, { required_authority: "ci" }, "release", {
      required_for_release: false,
      trusted_producer: "trusted-ci-prover"
    });
    expect(row.status).toBe("FRESH");
    expect(row.policy_block).toBe(false);
  });
});
