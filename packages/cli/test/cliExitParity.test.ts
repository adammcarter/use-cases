// BLOCKER 2 (end-to-end) — the process EXIT CODE must be IDENTICAL in --json and
// human mode, and the human view must not read as unqualified success when the
// command failed. Drives the REAL `runCli` dispatcher over a real workspace and
// captures both stdout + the returned exit code in each mode.
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, appendFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test, vi } from "vitest";
import { runCli } from "../src/index.js";

const CONFIG_YAML = `schema_version: 1
workspace_id: markers.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: presentation-skills
default_workflow_mode: continuous
`;

const ROW_A = "checkout.apply_coupon";
const USE_CASE_YAML = `schema_version: 1
feature:
  id: checkout
  name: Checkout
  summary: Shoppers can apply coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
  - id: ${ROW_A}
    title: Apply a valid coupon
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Apply a valid coupon to a cart.
    preconditions:
      - A cart exists.
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${ROW_A}.web
        kind: steps
        steps:
          - The shopper submits a coupon code.
    observable_outcomes:
      - The cart total reflects the discount.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        coupon_check:
          kind: script
          evidence_kind: test_result
          command: [echo, coupon-ok]
          inputs: []
      requirements:
        - evidence_kind: test_result
          required_verifiers: [coupon_check]
          minimum_count: 1
    approval_policy:
      mode: none
`;

const SWIFT_A = `import Foundation

@MainActor
public func applyCoupon(_ code: String) async throws -> Int {
    return 1
}
`;

const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
  vi.restoreAllMocks();
});

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

function makeWorkspace(): string {
  const root = mkdtempSync(join(tmpdir(), "ucm-parity-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_A);
  return root;
}

// Run the real CLI, capturing stdout and the returned exit code.
function run(argv: string[]): { exit: number; out: string } {
  let out = "";
  const spy = vi.spyOn(process.stdout, "write").mockImplementation((chunk: unknown) => {
    out += String(chunk);
    return true;
  });
  try {
    const exit = runCli(argv);
    return { exit, out };
  } finally {
    spy.mockRestore();
  }
}

// The affirmative-without-failure heuristic from render.test.ts.
function looksUnqualifiedGreen(text: string): boolean {
  const hasFailureMarker = /✗|FAILED|\bfailed\b/i.test(text);
  const hasSuccessMarker = /✓|\bfresh\b/i.test(text);
  return hasSuccessMarker && !hasFailureMarker;
}

describe("BLOCKER 2 — exit-code parity between --json and human mode (real runCli)", () => {
  test("a bound row scans clean: exit code is IDENTICAL in --json and human mode (0)", () => {
    const root = makeWorkspace();
    // bind + verify so the keyless VERIFIED_LOCAL tier is live (no key, no proofs).
    expect(run(["bind", "--repo", root, "--row", ROW_A, "--file", "Sources/Checkout/CouponService.swift", "--mode", "swift-func", "--line", "3"]).exit).toBe(0);
    expect(run(["verify", "--repo", root, "--row", ROW_A]).exit).toBe(0);

    const json = run(["scan", "--repo", root, "--json"]);
    const human = run(["scan", "--repo", root]);
    expect(human.exit).toBe(json.exit);
    expect(human.exit).toBe(0);
    // Clean scan: the human green view is truthful.
    expect(human.out).toMatch(/✓/);
  });

  test("a CORRUPT evidence ledger: exit code is IDENTICAL in --json and human mode (4), and the human view surfaces the failure", () => {
    const root = makeWorkspace();
    run(["bind", "--repo", root, "--row", ROW_A, "--file", "Sources/Checkout/CouponService.swift", "--mode", "swift-func", "--line", "3"]);
    run(["verify", "--repo", root, "--row", ROW_A]);
    // Corrupt the evidence ledger with a malformed JSONL line -> real integrity failure.
    appendFileSync(join(root, ".use-cases", "proofs.jsonl"), "{ not valid json\n");

    const json = run(["scan", "--repo", root, "--json"]);
    const human = run(["scan", "--repo", root]);

    // Parity: same non-zero exit in both modes.
    expect(json.exit).not.toBe(0);
    expect(human.exit).toBe(json.exit);

    // The --json envelope reports the failure...
    expect(JSON.parse(json.out).ok).toBe(false);
    // ...and the human view must NOT read as unqualified success.
    expect(looksUnqualifiedGreen(human.out)).toBe(false);
  });

  test("verify a bound row WITHOUT --public-key succeeds in both modes (BLOCKER 2b end-to-end)", () => {
    const root = makeWorkspace();
    run(["bind", "--repo", root, "--row", ROW_A, "--file", "Sources/Checkout/CouponService.swift", "--mode", "swift-func", "--line", "3"]);
    // First verify lands a results ledger; now land a signed proof would need a key,
    // so instead assert verify itself runs clean with no key and reports the row.
    const json = run(["verify", "--repo", root, "--all", "--json"]);
    const human = run(["verify", "--repo", root, "--all"]);
    expect(human.exit).toBe(json.exit);
    expect(json.exit).toBe(0);
    // The bound row is verified (never "no bound behaviours to verify").
    expect(human.out).not.toMatch(/no bound behaviours to verify/);
    expect(JSON.parse(json.out).data.results.map((r: { row_id: string }) => r.row_id)).toContain(ROW_A);
  });
});
