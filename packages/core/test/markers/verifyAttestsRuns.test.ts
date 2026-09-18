// The two experiments, at core scale.
//
// A measurement against a real repo found the acceptance claim rewarded the
// forgeable path and ignored the real one: typing ONE fake line into
// `.use-cases/verification-results.jsonl` moved the number from 285 to 286
// (nothing ran; the recorded stdout hash was literally `sha256:de1e7e…dead`),
// while five genuinely hand-driven evidence records moved it not at all.
//
// This suite pins the reversal on the ledger `scan` actually reads:
//   * a line `verify` wrote (having spawned the verifier) counts;
//   * a line a text editor wrote does not, however perfect its hashes.
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runScanCommand,
  runVerifyCommand,
  singleKeyResolver,
  type VerifySpawnRunner
} from "../../src/markers/index.js";
import { generateKeyPairSync } from "node:crypto";

const ROW_A = "checkout.apply_coupon";
const ROW_B = "checkout.refund_order";
const GENERATED_AT = "2026-06-28T12:10:00.000Z";

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
  - id: ${ROW_B}
    title: Refund an order
    lifecycle: active
    value_tier: core
    journey_role: edge
    usage_frequency: occasional
    actor: shopper
    intent: Refund a completed order.
    preconditions:
      - An order exists.
    trigger: The shopper requests a refund.
    scenarios:
      - id: ${ROW_B}.web
        kind: steps
        steps:
          - The shopper requests a refund.
    observable_outcomes:
      - The order total is refunded.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      verifiers:
        refund_check:
          kind: script
          evidence_kind: test_result
          command: [echo, refund-ok]
          inputs: []
      requirements:
        - evidence_kind: test_result
          required_verifiers: [refund_check]
          minimum_count: 1
    approval_policy:
      mode: none
`;

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

const SWIFT_A = `import Foundation

@MainActor
public func applyCoupon(_ code: String) async throws -> Int {
    return 1
}
`;

const SWIFT_B = `import Foundation

@MainActor
public func refundOrder(_ id: String) async throws -> Int {
    return 2
}
`;

const resolver = singleKeyResolver(generateKeyPairSync("ed25519").publicKey);
const tempDirs: string[] = [];

afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

function makeWorkspace() {
  const root = mkdtempSync(join(tmpdir(), "ucm-attest-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_A);
  writeFile(root, "Sources/Checkout/RefundService.swift", SWIFT_B);
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  // The machine-local run key lives OUTSIDE the repo in production; here it goes
  // in the throwaway workspace so the suite never touches the real home dir.
  const runKeyPath = join(root, "machine-key", "run-key");
  return {
    root,
    runKeyPath,
    resultsPath: join(root, "results.jsonl"),
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl"),
    context
  };
}

type Workspace = ReturnType<typeof makeWorkspace>;

let idCounter = 0;
function bind(ws: Workspace, rowId: string, file: string): void {
  const result = runBindCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    rowId,
    file,
    mode: "swift-func",
    line: 3,
    clock: () => GENERATED_AT,
    idFactory: () => `01JBIND${String(idCounter++).padStart(18, "0")}`
  });
  expect(result.exit_code).toBe(0);
}

const passSpawn: VerifySpawnRunner = () => ({
  exit_code: 0,
  timed_out: false,
  stdout: "ok\n",
  stderr: ""
});

function verify(ws: Workspace, rowId: string) {
  return runVerifyCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    trustedKeyConfigured: false,
    generatedAt: GENERATED_AT,
    rowId,
    outPath: ws.resultsPath,
    runKeyPath: ws.runKeyPath,
    spawnRunner: passSpawn
  });
}

function scan(ws: Workspace) {
  return runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    trustedKeyConfigured: false,
    generatedAt: GENERATED_AT,
    resultsPath: ws.resultsPath,
    runKeyPath: ws.runKeyPath,
    policyMode: "feature"
  });
}

function localStatusOf(status: ReturnType<typeof scan>, rowId: string) {
  return status.status.rows.find((row) => row.row_id === rowId)?.local_status ?? null;
}

function readLedger(ws: Workspace): Record<string, unknown>[] {
  return readFileSync(ws.resultsPath, "utf8")
    .split("\n")
    .filter((line) => line.trim() !== "")
    .map((line) => JSON.parse(line) as Record<string, unknown>);
}

function writeLedger(ws: Workspace, records: Record<string, unknown>[]): void {
  writeFileSync(ws.resultsPath, `${records.map((record) => JSON.stringify(record)).join("\n")}\n`);
}

describe("verify attests what it ran", () => {
  test("every emitted record carries a run attestation", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    verify(ws, ROW_A);

    const [record] = readLedger(ws);
    expect(record.run_attestation).toMatch(/^hmac-sha256:[0-9a-f]{64}$/);
  });

  test("a verified row reads VERIFIED_LOCAL and is counted as proven", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    verify(ws, ROW_A);

    const status = scan(ws);
    expect(localStatusOf(status, ROW_A)).toBe("VERIFIED_LOCAL");
    expect(status.status.acceptance_claim.proven).toBe(1);
  });
});

describe("EXPERIMENT 1: typing a line must not move the number", () => {
  test("a hand-written record with byte-perfect hashes proves nothing", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");

    // Verify both rows for real, then strip ROW_B's attestation — which is
    // exactly what a hand-written line looks like: every hash correct (they were
    // copied from a genuine record), no proof a run produced it.
    verify(ws, ROW_A);
    verify(ws, ROW_B);
    const before = scan(ws).status.acceptance_claim.proven;
    expect(before).toBe(2);

    const forged = readLedger(ws).map((record) =>
      record.row_id === ROW_B ? { ...record, run_attestation: undefined } : record
    );
    writeLedger(ws, forged);

    const after = scan(ws);
    expect(localStatusOf(after, ROW_B)).toBe("UNATTESTED_LOCAL");
    expect(after.status.acceptance_claim.proven).toBe(1);
    expect(after.status.summary.unattested_local).toBe(1);
  });

  test("editing a FAILED record to say pass does not launder it", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    runVerifyCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      trustedKeyConfigured: false,
      generatedAt: GENERATED_AT,
      rowId: ROW_A,
      outPath: ws.resultsPath,
      runKeyPath: ws.runKeyPath,
      spawnRunner: () => ({ exit_code: 1, timed_out: false, stdout: "", stderr: "boom\n" })
    });
    expect(scan(ws).status.acceptance_claim.proven).toBe(0);

    // Flip the verdict, keep the (genuine, but now mismatched) attestation.
    writeLedger(
      ws,
      readLedger(ws).map((record) => ({ ...record, status: "pass", exit_code: 0 }))
    );

    const after = scan(ws);
    expect(localStatusOf(after, ROW_A)).toBe("UNATTESTED_LOCAL");
    expect(after.status.acceptance_claim.proven).toBe(0);
  });

  test("a ledger from another machine reads unattested, not verified", () => {
    // The results ledger is transient per-machine output (`use-cases init` gitignores
    // it). One committed by a teammate is their run, not yours.
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    verify(ws, ROW_A);
    expect(scan(ws).status.acceptance_claim.proven).toBe(1);

    // Same ledger, different machine: point scan at a key file that does not
    // exist, as it would not on a fresh clone.
    const elsewhere = runScanCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      trustedKeyConfigured: false,
      generatedAt: GENERATED_AT,
      resultsPath: ws.resultsPath,
      runKeyPath: join(ws.root, "some-other-machine", "run-key"),
      policyMode: "feature"
    });
    expect(localStatusOf(elsewhere, ROW_A)).toBe("UNATTESTED_LOCAL");
    expect(elsewhere.status.acceptance_claim.proven).toBe(0);
  });

  test("scan never mints a key: it is read-only, and a read-only tool cannot attest", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const keyPath = join(ws.root, "never-written", "run-key");
    runScanCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      trustedKeyConfigured: false,
      generatedAt: GENERATED_AT,
      resultsPath: ws.resultsPath,
      runKeyPath: keyPath,
      policyMode: "feature"
    });
    expect(() => readFileSync(keyPath, "utf8")).toThrow();
  });
});

describe("EXPERIMENT 2: a genuine run must move the number", () => {
  test("running the verifier for real takes a row from unattested to proven", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    verify(ws, ROW_A);
    verify(ws, ROW_B);
    writeLedger(
      ws,
      readLedger(ws).map((record) =>
        record.row_id === ROW_B ? { ...record, run_attestation: undefined } : record
      )
    );
    expect(scan(ws).status.acceptance_claim.proven).toBe(1);

    // Now actually run it. The number moves, and it moves because a process ran.
    verify(ws, ROW_B);
    const after = scan(ws);
    expect(localStatusOf(after, ROW_B)).toBe("VERIFIED_LOCAL");
    expect(after.status.acceptance_claim.proven).toBe(2);
  });
});
