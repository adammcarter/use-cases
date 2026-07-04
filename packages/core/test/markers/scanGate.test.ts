// `scan --gate` exit-code gating helper (Task 2, 0.1.0 keyless daily loop).
//
// `evaluateScanGate` is a PURE decision over an already-derived FreshnessStatus:
// with the gate on, a REQUIRED row below the mode's acceptable bar blocks (exit
// 1) and is listed as an offender. The bar is FRESH in `release` policy mode and
// "at least VERIFIED_LOCAL" (VERIFIED_LOCAL or FRESH) otherwise. Non-required
// rows never block; without the gate nothing blocks. This is additive and never
// changes the signed `status` or the existing scanExitCode precedence.
import { describe, expect, test } from "vitest";
import {
  evaluateScanGate,
  validateFreshnessStatus,
  type FreshnessRowOut,
  type FreshnessStatus,
  type LocalStatus,
  type PolicyMode,
  type RowStatus
} from "../../src/markers/index.js";

function makeRow(
  overrides: Partial<FreshnessRowOut> & { row_id: string; status: RowStatus }
): FreshnessRowOut {
  return {
    policy_block: false,
    reasons: [],
    known_binding_slugs: [],
    current_binding_slugs: [],
    missing_registered_binding_slugs: [],
    unregistered_current_binding_slugs: [],
    current_bindings: [],
    matching_proof_event: null,
    latest_trusted_proof_event: null,
    required_action: null,
    ...overrides
  };
}

function makeStatus(
  rows: FreshnessRowOut[],
  policyMode: PolicyMode = "feature"
): FreshnessStatus {
  return {
    schema: "ucase-freshness-status-v1" as FreshnessStatus["schema"],
    generated_at: "2026-07-03T00:00:00Z",
    tool: { name: "use-cases", version: "0.0.0" },
    product_root: ".",
    policy_mode: policyMode,
    guard_ok: true,
    summary: {
      fresh: 0,
      suspect: 0,
      unproven: 0,
      unbound: 0,
      invalid: 0,
      policy_blocked: 0
    },
    integrity_errors: [],
    rows
  };
}

function requiredRow(
  status: RowStatus,
  local: LocalStatus | null,
  rowId = "r1"
): FreshnessRowOut {
  return makeRow({
    row_id: rowId,
    status,
    required_for_release: true,
    local_status: local,
    local_reason: null
  });
}

describe("evaluateScanGate (dev/feature bar = at least VERIFIED_LOCAL)", () => {
  test("a required VERIFIED_LOCAL row passes the gate", () => {
    const status = makeStatus([requiredRow("UNPROVEN", "VERIFIED_LOCAL")]);
    const result = evaluateScanGate(status, "feature");
    expect(result.blocked).toBe(false);
    expect(result.offending_rows).toEqual([]);
  });

  test("a required UNVERIFIED_LOCAL row blocks (exit 1)", () => {
    const status = makeStatus([requiredRow("UNPROVEN", "UNVERIFIED_LOCAL")]);
    const result = evaluateScanGate(status, "feature");
    expect(result.blocked).toBe(true);
    expect(result.offending_rows.map((r) => r.row_id)).toEqual(["r1"]);
    expect(result.offending_rows[0].local_status).toBe("UNVERIFIED_LOCAL");
  });

  test("a required STALE_LOCAL row blocks", () => {
    const status = makeStatus([requiredRow("SUSPECT", "STALE_LOCAL")]);
    expect(evaluateScanGate(status, "feature").blocked).toBe(true);
  });

  test("a required FRESH row passes (FRESH outranks the local bar)", () => {
    const status = makeStatus([requiredRow("FRESH", "VERIFIED_LOCAL")]);
    expect(evaluateScanGate(status, "feature").blocked).toBe(false);
  });

  test("a NON-required SUSPECT row never blocks the gate", () => {
    const status = makeStatus([
      makeRow({ row_id: "r1", status: "SUSPECT", required_for_release: false, local_status: "STALE_LOCAL" })
    ]);
    expect(evaluateScanGate(status, "feature").blocked).toBe(false);
  });
});

describe("evaluateScanGate (release bar = FRESH)", () => {
  test("a required VERIFIED_LOCAL row blocks in release mode (bar is FRESH)", () => {
    const status = makeStatus([requiredRow("UNPROVEN", "VERIFIED_LOCAL")], "release");
    expect(evaluateScanGate(status, "release").blocked).toBe(true);
  });

  test("a required FRESH row passes in release mode", () => {
    const status = makeStatus([requiredRow("FRESH", "VERIFIED_LOCAL")], "release");
    expect(evaluateScanGate(status, "release").blocked).toBe(false);
  });
});

describe("required_for_release on the row output validates against the schema", () => {
  test("a status carrying required_for_release passes validateFreshnessStatus", () => {
    const status = makeStatus([
      requiredRow("UNPROVEN", "VERIFIED_LOCAL", "r1"),
      makeRow({ row_id: "r2", status: "UNBOUND", required_for_release: false, local_status: null, local_reason: null })
    ]);
    const result = validateFreshnessStatus(status);
    expect(result.errors).toEqual([]);
    expect(result.ok).toBe(true);
  });
});

describe("evaluateScanGate offender ordering + multiple rows", () => {
  test("lists every offending required row and ignores acceptable ones", () => {
    const status = makeStatus([
      requiredRow("FRESH", "VERIFIED_LOCAL", "ok1"),
      requiredRow("UNPROVEN", "UNVERIFIED_LOCAL", "bad1"),
      requiredRow("UNPROVEN", "VERIFIED_LOCAL", "ok2"),
      requiredRow("SUSPECT", "STALE_LOCAL", "bad2")
    ]);
    const result = evaluateScanGate(status, "feature");
    expect(result.blocked).toBe(true);
    expect(result.offending_rows.map((r) => r.row_id)).toEqual(["bad1", "bad2"]);
  });
});
