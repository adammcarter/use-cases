import { accessSync, constants, readFileSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { describe, expect, test } from "vitest";
import {
  decidePrecommit,
  formatFreshnessPrSummary,
  type PrecommitInput
} from "../../src/markers/cli/precommit.js";
import { STATUS_SCHEMA_ID } from "../../src/markers/constants.js";
import type {
  CurrentBindingOut,
  FreshnessRowOut,
  FreshnessStatus,
  FreshnessSummary,
  PolicyMode,
  RowStatus
} from "../../src/markers/freshness.js";
import type { ValidateLedgerCommandResult } from "../../src/markers/cli/validateLedger.js";

// ---------------------------------------------------------------------------
// Builders: hand-construct the two command results so the orchestrator and the
// PR-summary formatter are tested as PURE functions (no fs, no git, no CLI).
// ---------------------------------------------------------------------------

function makeRow(partial: Partial<FreshnessRowOut> & { row_id: string; status: RowStatus }): FreshnessRowOut {
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
    ...partial
  };
}

function makeStatus(rows: FreshnessRowOut[], policy_mode: PolicyMode = "feature"): FreshnessStatus {
  const summary: FreshnessSummary = {
    fresh: 0,
    suspect: 0,
    unproven: 0,
    unbound: 0,
    invalid: 0,
    policy_blocked: 0
  };
  for (const row of rows) {
    switch (row.status) {
      case "FRESH":
        summary.fresh += 1;
        break;
      case "SUSPECT":
        summary.suspect += 1;
        break;
      case "UNPROVEN":
        summary.unproven += 1;
        break;
      case "UNBOUND":
        summary.unbound += 1;
        break;
      case "INVALID":
        summary.invalid += 1;
        break;
    }
    if (row.policy_block) {
      summary.policy_blocked += 1;
    }
  }
  return {
    schema: STATUS_SCHEMA_ID,
    generated_at: "2026-06-28T12:10:00.000Z",
    tool: { name: "use-cases", version: "0.1.0" },
    product_root: ".",
    policy_mode,
    guard_ok: summary.invalid === 0,
    summary,
    integrity_errors: [],
    rows
  };
}

function makeValidateLedger(partial: Partial<ValidateLedgerCommandResult> = {}): ValidateLedgerCommandResult {
  return {
    exit_code: 0,
    ok: true,
    command: "validate-ledger",
    evidence_valid: true,
    registry_valid: true,
    append_only: true,
    proof_events_checked: 0,
    registry_events_checked: 0,
    errors: [],
    ...partial
  };
}

function makeInput(
  scanStatus: FreshnessStatus,
  validateLedger: ValidateLedgerCommandResult = makeValidateLedger(),
  scanOverrides: Partial<PrecommitInput["scan"]> = {}
): PrecommitInput {
  return {
    validateLedger,
    scan: {
      exit_code: scanStatus.summary.invalid > 0 ? 3 : 0,
      registry_valid: true,
      evidence_valid: true,
      status: scanStatus,
      ...scanOverrides
    }
  };
}

const SWIFT_BINDING: CurrentBindingOut = {
  binding_slug: "checkout.apply_coupon#handler",
  file_path: "Sources/Checkout/CouponService.swift",
  extent_kind: "swift_func_inferred",
  recognizer_id: "swift-func-inferred-v1",
  span_canon_id: "ucase-span-lines-v2",
  span_sha256: "sha256:abc",
  span_start_line: 13,
  span_end_line: 27
};

describe("decidePrecommit orchestrator (spec 10.1)", () => {
  test("acceptance 1: BLOCKS on a malformed marker (scan INVALID integrity failure)", () => {
    const status = makeStatus([
      makeRow({
        row_id: "checkout.apply_coupon",
        status: "INVALID",
        policy_block: true,
        reasons: [{ code: "MARKER_MALFORMED", message: "malformed marker payload" }]
      })
    ]);
    const result = decidePrecommit(makeInput(status, makeValidateLedger(), { exit_code: 3 }));
    expect(result.decision).toBe("BLOCK");
    expect(result.exit_code).toBe(1);
    expect(result.block_reasons.some((reason) => reason.code === "MARKER_MALFORMED")).toBe(true);
  });

  test("acceptance 2: BLOCKS on a non-append ledger edit reported by validate-ledger", () => {
    const status = makeStatus([makeRow({ row_id: "checkout.apply_coupon", status: "FRESH" })]);
    const validateLedger = makeValidateLedger({
      exit_code: 4,
      ok: false,
      evidence_valid: false,
      append_only: false,
      errors: [
        {
          scope: "evidence",
          code: "APPEND_ONLY_VIOLATION",
          line: 1,
          message: "evidence line 1 was edited or deleted"
        }
      ]
    });
    const result = decidePrecommit(makeInput(status, validateLedger));
    expect(result.decision).toBe("BLOCK");
    expect(result.exit_code).toBe(1);
    expect(
      result.block_reasons.some(
        (reason) => reason.source === "validate-ledger" && reason.code === "APPEND_ONLY_VIOLATION"
      )
    ).toBe(true);
  });

  test("acceptance 3: WARNS but does not block a SUSPECT row, emitting the required-action message", () => {
    const status = makeStatus([
      makeRow({
        row_id: "checkout.apply_coupon",
        status: "SUSPECT",
        policy_block: false,
        reasons: [{ code: "CODE_SPAN_CHANGED", binding_slug: "checkout.apply_coupon#handler" }],
        required_action: "use-cases prove --row checkout.apply_coupon"
      })
    ]);
    const result = decidePrecommit(makeInput(status, makeValidateLedger(), { exit_code: 0 }));
    expect(result.decision).toBe("WARN");
    expect(result.exit_code).toBe(0);
    expect(result.block_reasons).toHaveLength(0);
    expect(result.warnings).toHaveLength(1);
    const message = result.warnings[0].message;
    expect(message).toContain("USE-CASE ROW SUSPECT");
    expect(message).toContain("row: checkout.apply_coupon");
    expect(message).toContain("reason: CODE_SPAN_CHANGED");
    expect(message).toContain("required action: use-cases prove --row checkout.apply_coupon");
  });

  test("acceptance 4: feature mode blocks INVALID only; SUSPECT/UNPROVEN do not block", () => {
    const status = makeStatus(
      [
        makeRow({
          row_id: "checkout.invalid_row",
          status: "INVALID",
          policy_block: true,
          reasons: [{ code: "UNREGISTERED_BINDING" }]
        }),
        makeRow({
          row_id: "checkout.suspect_row",
          status: "SUSPECT",
          policy_block: false,
          reasons: [{ code: "BINDING_REMOVED" }],
          required_action: "use-cases prove --row checkout.suspect_row"
        }),
        makeRow({
          row_id: "checkout.unproven_row",
          status: "UNPROVEN",
          policy_block: false,
          required_action: "use-cases prove --row checkout.unproven_row"
        })
      ],
      "feature"
    );
    const result = decidePrecommit(makeInput(status, makeValidateLedger(), { exit_code: 3 }));
    expect(result.decision).toBe("BLOCK");
    // Only the INVALID row contributes a block reason.
    expect(result.block_reasons.every((reason) => reason.code !== "BINDING_REMOVED")).toBe(true);
    expect(result.block_reasons.some((reason) => reason.code === "UNREGISTERED_BINDING")).toBe(true);
    // SUSPECT + UNPROVEN remain warnings.
    expect(result.warnings.map((warning) => warning.row_id).sort()).toEqual([
      "checkout.suspect_row",
      "checkout.unproven_row"
    ]);
  });

  test("acceptance 5: release mode blocks a required row that is not FRESH", () => {
    const status = makeStatus(
      [
        makeRow({
          row_id: "checkout.apply_coupon",
          status: "SUSPECT",
          // deriveFreshness sets policy_block for a required, non-FRESH row in release mode.
          policy_block: true,
          reasons: [{ code: "CODE_SPAN_CHANGED" }],
          required_action: "use-cases prove --row checkout.apply_coupon"
        })
      ],
      "release"
    );
    const result = decidePrecommit(makeInput(status, makeValidateLedger(), { exit_code: 1 }));
    expect(result.decision).toBe("BLOCK");
    expect(result.exit_code).toBe(1);
    expect(
      result.block_reasons.some((reason) => reason.source === "scan" && reason.code === "FRESHNESS_POLICY_BLOCK")
    ).toBe(true);
  });

  test("a clean status with no rows of concern is OK", () => {
    const status = makeStatus([makeRow({ row_id: "checkout.apply_coupon", status: "FRESH" })]);
    const result = decidePrecommit(makeInput(status));
    expect(result.decision).toBe("OK");
    expect(result.exit_code).toBe(0);
    expect(result.block_reasons).toHaveLength(0);
    expect(result.warnings).toHaveLength(0);
  });
});

describe("formatFreshnessPrSummary (PR-summary formatter)", () => {
  test("acceptance 6: renders counts, SUSPECT/INVALID rows + required action, and inferred Swift spans", () => {
    const status = makeStatus([
      makeRow({
        row_id: "checkout.apply_coupon",
        status: "FRESH",
        current_bindings: [SWIFT_BINDING]
      }),
      makeRow({
        row_id: "checkout.suspect_row",
        status: "SUSPECT",
        reasons: [{ code: "CODE_SPAN_CHANGED", binding_slug: "checkout.suspect_row#handler" }],
        required_action: "use-cases prove --row checkout.suspect_row"
      }),
      makeRow({
        row_id: "checkout.invalid_row",
        status: "INVALID",
        reasons: [{ code: "UNREGISTERED_BINDING" }],
        required_action: "use-cases scan (resolve binding integrity errors)"
      })
    ]);
    const summary = formatFreshnessPrSummary(status);

    // Counts.
    expect(summary).toContain("fresh: 1");
    expect(summary).toContain("suspect: 1");
    expect(summary).toContain("invalid: 1");

    // SUSPECT row + required action.
    expect(summary).toContain("checkout.suspect_row");
    expect(summary).toContain("CODE_SPAN_CHANGED");
    expect(summary).toContain("use-cases prove --row checkout.suspect_row");

    // INVALID row + required action.
    expect(summary).toContain("checkout.invalid_row");
    expect(summary).toContain("UNREGISTERED_BINDING");

    // Inferred Swift span block.
    expect(summary).toContain("INFERRED SWIFT SPAN");
    expect(summary).toContain("checkout.apply_coupon#handler");
    expect(summary).toContain("Sources/Checkout/CouponService.swift");
    expect(summary).toContain("lines 13-27");
    expect(summary).toContain("sha256:abc");
  });
});

describe("precommit shell script (smoke)", () => {
  // packages/core/test/markers -> repo root is four levels up.
  const repoRoot = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "..");
  const scriptPath = join(repoRoot, "scripts", "use-cases-precommit.sh");

  test("acceptance 7: exists, is executable, and references both CLI commands", () => {
    const stats = statSync(scriptPath);
    expect(stats.isFile()).toBe(true);
    // Owner-executable bit set.
    expect(stats.mode & 0o100).toBe(0o100);
    // POSIX exec permission also resolvable.
    expect(() => accessSync(scriptPath, constants.X_OK)).not.toThrow();

    const contents = readFileSync(scriptPath, "utf8");
    expect(contents).toContain("validate-ledger");
    expect(contents).toContain("scan");
    expect(contents).toContain("--policy-mode feature");
  });
});
