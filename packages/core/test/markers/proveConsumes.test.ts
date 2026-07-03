// PIECE 4: `prove` consumes verification-result records (it no longer runs the
// verifier scripts itself) and gains `--all`.
//
// These tests drive the real PIECE 3 -> PIECE 4 pipeline: `verify` mints unsigned
// `ucase-verification-result-v1` records (through an injected spawn runner, so
// nothing shells out), then `prove` CONSUMES them. prove appends a signed proof
// only when a row's latest matching result is status:pass AND prove's OWN freshly
// recomputed hashes equal the hashes the record carries. A stale/blocked/failed/
// missing result yields no proof and a nonzero exit, while passing rows in the
// same `--all` run are still appended (non-atomic).
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runProveCommand,
  runScanCommand,
  runVerifyCommand,
  singleKeyResolver,
  type VerificationResultRecord,
  type VerifySpawnRunner
} from "../../src/markers/index.js";

const ROW_A = "checkout.apply_coupon";
const ROW_B = "checkout.refund_order";
const ROW_C = "checkout.unresolved_verifier";
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
  - id: ${ROW_C}
    title: Row with an undeclared verifier
    lifecycle: active
    value_tier: core
    journey_role: edge
    usage_frequency: occasional
    actor: shopper
    intent: A row whose required verifier id is not declared.
    preconditions:
      - Something exists.
    trigger: The shopper does a thing.
    scenarios:
      - id: ${ROW_C}.web
        kind: steps
        steps:
          - The shopper does a thing.
    observable_outcomes:
      - Something observable happens.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: test_result
          required_verifiers: [no_such_verifier]
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

const SWIFT_C = `import Foundation

@MainActor
public func doAThing() async throws -> Int {
    return 3
}
`;

const keypair = generateKeyPairSync("ed25519");
const PUBLIC_KEY: KeyObject = keypair.publicKey;
const PRIVATE_KEY: KeyObject = keypair.privateKey;
const KEY_ID = "trusted-ci-test";
const resolver = singleKeyResolver(PUBLIC_KEY);

const tempDirs: string[] = [];

afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

interface Workspace {
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  context: ReturnType<typeof resolveWorkspaceContext>;
}

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

function makeWorkspace(): Workspace {
  const root = mkdtempSync(join(tmpdir(), "ucm-prove-consume-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_A);
  writeFile(root, "Sources/Checkout/RefundService.swift", SWIFT_B);
  writeFile(root, "Sources/Checkout/ThingService.swift", SWIFT_C);
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl"),
    context
  };
}

let idCounter = 0;
function makeId(prefix: string): () => string {
  return () => `${prefix}${String(idCounter++).padStart(26 - prefix.length, "0")}`;
}

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
    idFactory: makeId("01JBIND")
  });
  expect(result.exit_code).toBe(0);
}

const passSpawn: VerifySpawnRunner = () => ({
  exit_code: 0,
  timed_out: false,
  stdout: "ok\n",
  stderr: ""
});

// Mint a real results ledger for the given target(s) via `verify` (no shelling
// out — passSpawn decides). Returns the in-memory records prove will consume.
function mintResults(ws: Workspace, opts: { all?: boolean; rowId?: string } = { all: true }): VerificationResultRecord[] {
  const result = runVerifyCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT,
    spawnRunner: passSpawn,
    ...opts
  });
  return result.results;
}

function proveBase(ws: Workspace) {
  return {
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT,
    idFactory: makeId("01JPROVE"),
    signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID }
  };
}

function scan(ws: Workspace) {
  return runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode: "feature" as const,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
}

function rowStatus(result: ReturnType<typeof runScanCommand>, rowId: string): string {
  const row = result.status.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} missing from status`);
  }
  return row.status;
}

function proveRow(result: ReturnType<typeof runProveCommand>, rowId: string) {
  const row = result.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} missing from prove result`);
  }
  return row;
}

describe("prove --all consumes verification results", () => {
  test("signs every bound passing row (sorted) and skips UNBOUND rows", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    // ROW_C is left UNBOUND.
    const results = mintResults(ws, { all: true });

    const result = runProveCommand({
      ...proveBase(ws),
      all: true,
      trustedCi: true,
      verificationResults: results
    });

    expect(result.exit_code).toBe(0);
    expect(result.proof_events_appended).toBe(2);
    expect(proveRow(result, ROW_A).status).toBe("signed");
    expect(proveRow(result, ROW_B).status).toBe("signed");
    expect(proveRow(result, ROW_C).status).toBe("skipped_unbound");

    const evidence = readFileSync(ws.evidencePath, "utf8").trim().split("\n");
    expect(evidence).toHaveLength(2);

    const afterProve = scan(ws);
    expect(rowStatus(afterProve, ROW_A)).toBe("FRESH");
    expect(rowStatus(afterProve, ROW_B)).toBe("FRESH");
  });

  test("a signed proof embeds the SAME verification_context_hash the result carries", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });
    const recordHash = results.find((record) => record.row_id === ROW_A)!.verification_context_hash;
    expect(recordHash).toMatch(/^sha256:[0-9a-f]{64}$/);

    const result = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: results
    });
    expect(proveRow(result, ROW_A).status).toBe("signed");

    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    expect(event.verification.context_hash_id).toBe("ucase-verification-context-hash-v1");
    expect(event.verification.context_hash).toBe(recordHash);
  });

  test("a targeted row with NO matching result fails (nonzero) while passing rows still get appended", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    const results = mintResults(ws, { all: true })
      // Drop ROW_B's result -> it has no passing result.
      .filter((record) => record.row_id !== ROW_B);

    const result = runProveCommand({
      ...proveBase(ws),
      all: true,
      trustedCi: true,
      verificationResults: results
    });

    expect(result.exit_code).not.toBe(0);
    expect(proveRow(result, ROW_A).status).toBe("signed");
    expect(proveRow(result, ROW_B).status).toBe("failed");
    expect(proveRow(result, ROW_B).reason).toBe("NO_PASSING_RESULT");
    // Non-atomic: ROW_A's proof is still appended.
    expect(result.proof_events_appended).toBe(1);
    expect(readFileSync(ws.evidencePath, "utf8").trim().split("\n")).toHaveLength(1);
  });

  test("a blocked result for a bound row fails (no proof)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_C, "Sources/Checkout/ThingService.swift");
    const results = mintResults(ws, { rowId: ROW_C });
    expect(results[0].status).toBe("blocked");

    const result = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_C,
      trustedCi: true,
      verificationResults: results
    });
    expect(result.exit_code).not.toBe(0);
    expect(proveRow(result, ROW_C).status).toBe("failed");
    expect(proveRow(result, ROW_C).reason).toBe("RESULT_BLOCKED");
    expect(existsSync(ws.evidencePath)).toBe(false);
  });

  test("prove recomputes hashes and refuses a result whose hashes don't match current code", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });
    // Tamper the result's row_hash: prove must recompute and refuse the mismatch.
    const tampered: VerificationResultRecord[] = results.map((record) => ({
      ...record,
      row_hash: `sha256:${"d".repeat(64)}`
    }));

    const result = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: tampered
    });
    expect(result.exit_code).not.toBe(0);
    expect(proveRow(result, ROW_A).status).toBe("failed");
    expect(proveRow(result, ROW_A).reason).toBe("HASH_MISMATCH");
    expect(existsSync(ws.evidencePath)).toBe(false);
  });

  test("an already-FRESH row is skipped unless --refresh", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });

    // First prove -> signed, FRESH.
    const first = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: results
    });
    expect(proveRow(first, ROW_A).status).toBe("signed");
    expect(rowStatus(scan(ws), ROW_A)).toBe("FRESH");

    // Second prove (no --refresh) -> skipped_fresh, no new proof.
    const second = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: results
    });
    expect(second.exit_code).toBe(0);
    expect(proveRow(second, ROW_A).status).toBe("skipped_fresh");
    expect(second.proof_events_appended).toBe(0);
    expect(readFileSync(ws.evidencePath, "utf8").trim().split("\n")).toHaveLength(1);

    // With --refresh -> re-signs (a second proof line).
    const third = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      refresh: true,
      verificationResults: results
    });
    expect(proveRow(third, ROW_A).status).toBe("signed");
    expect(readFileSync(ws.evidencePath, "utf8").trim().split("\n")).toHaveLength(2);
  });
});

describe("prove unsafe-assume seam is env-gated", () => {
  const ENV = "UCM_ALLOW_UNSAFE_VERIFICATION";
  let previous: string | undefined;

  beforeEach(() => {
    previous = process.env[ENV];
    delete process.env[ENV];
  });
  afterEach(() => {
    if (previous === undefined) {
      delete process.env[ENV];
    } else {
      process.env[ENV] = previous;
    }
  });

  test("the unsafe seam is REJECTED without the env var (no proof, nonzero)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");

    const result = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      unsafeAssumeVerificationResult: "pass"
      // no verificationResults, env var NOT set
    });
    expect(result.exit_code).not.toBe(0);
    expect(proveRow(result, ROW_A).status).toBe("failed");
    expect(existsSync(ws.evidencePath)).toBe(false);
  });

  test("the unsafe seam is honoured WITH the env var set (signs)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    process.env[ENV] = "1";

    const result = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      unsafeAssumeVerificationResult: "pass"
    });
    expect(result.exit_code).toBe(0);
    expect(proveRow(result, ROW_A).status).toBe("signed");
    expect(proveRow(result, ROW_A).event_id).toBeTruthy();

    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    expect(event.verification.context_hash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(rowStatus(scan(ws), ROW_A)).toBe("FRESH");
  });
});
