// Release-mode gating end-to-end (the `required_for_release` row-schema field).
//
// Before this change the use-case row schema's approval_policy used
// `additionalProperties: false`, so a row could not declare `required_for_release`
// at all -- release-mode freshness gating was inert on real rows even though the
// freshness engine supports it. These tests prove the full path now works:
//   YAML row with required_for_release -> schema accepts it -> loadMarkerRows
//   carries it -> deriveFreshness blocks a not-FRESH required row in release mode.
import { afterEach, describe, expect, test } from "vitest";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  deriveFreshness,
  loadMarkerRows,
  type CurrentBindingRecord,
  type MaterializedRegistry,
  type ScanResult
} from "../../src/markers/index.js";

const CONFIG_YAML = `schema_version: 1
workspace_id: release.gating.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: presentation-skills
default_workflow_mode: continuous
`;

// A config that opts into the CI-neutral release-gate authority requirement.
const CONFIG_YAML_WITH_AUTHORITY_GATE = `${CONFIG_YAML}release_gate:
  required_authority: ci
  require_protected_ref: true
`;

// A use-case file whose approval_policy declares required_for_release. `flag`
// toggles the value; omit it entirely when `flag` is null.
function rowYaml(flag: boolean | null): string {
  const line = flag === null ? "" : `\n      required_for_release: ${flag}`;
  return `schema_version: 1
feature: { id: checkout, name: Checkout, summary: Apply coupons. }
metadata: { owner: product, lifecycle: active }
use_cases:
  - id: checkout.apply_coupon
    title: Apply a valid coupon
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Apply a valid coupon to a cart.
    preconditions: [A cart exists.]
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: checkout.apply_coupon.web
        kind: steps
        steps: [Submit the code.]
    observable_outcomes: [The cart total reflects the discount.]
    host_applicability: [{ host_surface: codex.cli, supported: true }]
    verification_policy:
      mode: requirements
      requirements: [{ evidence_kind: live_demo, required_verifiers: [user], minimum_count: 1 }]
    approval_policy:
      mode: predefined${line}
      requirements: [{ approver_type: user, minimum_count: 1 }]
      statement: Final acceptance requires user-visible proof.
`;
}

const tmpDirs: string[] = [];
afterEach(() => {
  while (tmpDirs.length > 0) {
    const dir = tmpDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

function makeWorkspace(rowFlag: boolean | null): ReturnType<typeof resolveWorkspaceContext> {
  const root = mkdtempSync(join(tmpdir(), "ucm-relgate-"));
  tmpDirs.push(root);
  for (const [rel, body] of [
    ["presentation-skills.yml", CONFIG_YAML],
    ["use-cases/checkout.yml", rowYaml(rowFlag)]
  ] as const) {
    const full = join(root, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, body);
  }
  return resolveWorkspaceContext({ workspaceRoot: root });
}

// A registered, currently-marked binding with no proof -> the row is UNPROVEN
// (not FRESH), which is what release mode must block for a required row.
function unprovenInputs(): { registry: MaterializedRegistry; scan: ScanResult } {
  const slug = "checkout.apply_coupon";
  const binding: CurrentBindingRecord = {
    binding_slug: slug,
    row_id: "checkout.apply_coupon",
    suffix: null,
    file_path: "Sources/Checkout/CouponService.swift",
    comment_prefix: "//",
    extent_kind: "swift_func_inferred",
    recognizer_id: "swift-func-inferred-v1",
    span_canon_id: "ucase-span-lines-v1",
    start_marker: { line: 3, column: 1 },
    end_marker: null,
    span: { start_line: 4, end_line: 7, start_byte: 30, end_byte: 110, sha256: `sha256:${"a".repeat(64)}` },
    diagnostic: { symbol_kind: "swift_func", symbol_name: "applyCoupon", inferred: true }
  };
  const rowToSlugs = new Map([["checkout.apply_coupon", new Set([slug])]]);
  const slugToRow = new Map([[slug, "checkout.apply_coupon"]]);
  return { registry: { rowToSlugs, slugToRow }, scan: { files: [], bindings: [binding], errors: [] } };
}

function rowStatus(context: ReturnType<typeof resolveWorkspaceContext>, mode: "feature" | "release") {
  const loaded = loadMarkerRows(context);
  const { registry, scan } = unprovenInputs();
  const status = deriveFreshness({
    rows: loaded.rows,
    registry,
    scan,
    evidence: [],
    policy_mode: mode,
    generated_at: "2026-06-28T12:10:00Z",
    product_root: context.workspace_root
  });
  return { loaded, row: status.rows.find((r) => r.row_id === "checkout.apply_coupon") };
}

describe("release-mode gating via required_for_release", () => {
  test("a row may declare required_for_release without failing schema validation", () => {
    // The row loads (zero load diagnostics) and the flag survives into the row.
    const ctx = makeWorkspace(true);
    const { loaded } = rowStatus(ctx, "feature");
    expect(loaded.rowIds.has("checkout.apply_coupon")).toBe(true);
    const approval = (loaded.rows[0].approval_policy ?? {}) as Record<string, unknown>;
    expect(approval.required_for_release).toBe(true);
  });

  test("release mode BLOCKS a required, not-FRESH row", () => {
    const { row } = rowStatus(makeWorkspace(true), "release");
    expect(row?.status).toBe("UNPROVEN");
    expect(row?.policy_block).toBe(true);
  });

  test("release mode does NOT block when required_for_release is false", () => {
    const { row } = rowStatus(makeWorkspace(false), "release");
    expect(row?.status).toBe("UNPROVEN");
    expect(row?.policy_block).toBe(false);
  });

  test("release mode does NOT block when required_for_release is omitted", () => {
    const { row } = rowStatus(makeWorkspace(null), "release");
    expect(row?.policy_block).toBe(false);
  });

  test("feature mode never blocks a not-FRESH required row", () => {
    const { row } = rowStatus(makeWorkspace(true), "feature");
    expect(row?.policy_block).toBe(false);
  });
});

describe("release-gate authority requirement is read from workspace config", () => {
  function workspaceWith(configBody: string): ReturnType<typeof resolveWorkspaceContext> {
    const root = mkdtempSync(join(tmpdir(), "ucm-relgate-cfg-"));
    tmpDirs.push(root);
    for (const [rel, body] of [
      ["presentation-skills.yml", configBody],
      ["use-cases/checkout.yml", rowYaml(true)]
    ] as const) {
      const full = join(root, rel);
      mkdirSync(dirname(full), { recursive: true });
      writeFileSync(full, body);
    }
    return resolveWorkspaceContext({ workspaceRoot: root });
  }

  test("a configured release_gate is parsed onto the workspace context", () => {
    const ctx = workspaceWith(CONFIG_YAML_WITH_AUTHORITY_GATE);
    expect(ctx.release_gate).toEqual({ required_authority: "ci", require_protected_ref: true });
  });

  test("no release_gate in config leaves the context requirement undefined (off by default)", () => {
    const ctx = workspaceWith(CONFIG_YAML);
    expect(ctx.release_gate).toBeUndefined();
  });
});
