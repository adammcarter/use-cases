// PIECE 2 (v1 tamper-evident ledger): validate-ledger VERIFIES the hash chain
// over the contiguous chained suffix and detects every tamper class with stable
// UCM_LEDGER_* codes, while tolerating (and reporting) a leading legacy
// un-chained prefix.
//
// Each test builds a real signed ledger on disk via prove (so the chain fields
// are minted exactly as production would), then manipulates the JSONL and asserts
// the validate-ledger result.
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runProveCommand,
  runValidateLedgerCommand,
  runVerifyCommand,
  signEvent,
  singleKeyResolver,
  type ProofEvent,
  type VerificationResultRecord,
  type VerifySpawnRunner
} from "../../src/markers/index.js";

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
  const root = mkdtempSync(join(tmpdir(), "ucm-ledger-chain-validate-"));
  tempDirs.push(root);
  writeFile(root, "use-case-matrix.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_A);
  writeFile(root, "Sources/Checkout/RefundService.swift", SWIFT_B);
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

function mintResults(ws: Workspace, rowId: string): VerificationResultRecord[] {
  const result = runVerifyCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT,
    spawnRunner: passSpawn,
    rowId
  });
  return result.results;
}

function proveOne(ws: Workspace, rowId: string, refresh: boolean): void {
  const results = mintResults(ws, rowId);
  const result = runProveCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT,
    idFactory: makeId("01JPROVE"),
    signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
    rowId,
    trustedCi: true,
    refresh,
    verificationResults: results
  });
  expect(result.exit_code).toBe(0);
}

function readLines(ws: Workspace): string[] {
  return readFileSync(ws.evidencePath, "utf8")
    .trim()
    .split("\n")
    .filter((line) => line.trim() !== "");
}

function writeLines(ws: Workspace, lines: string[]): void {
  writeFileSync(ws.evidencePath, `${lines.join("\n")}\n`);
}

function parse(line: string): Record<string, unknown> {
  return JSON.parse(line) as Record<string, unknown>;
}

// Re-sign an event with the trusted key after mutating its body (so the
// signature stays valid and only the CHAIN is what fails).
function resign(event: Record<string, unknown>): string {
  const { signature, ...rest } = event;
  void signature;
  return JSON.stringify(signEvent(rest, PRIVATE_KEY, KEY_ID));
}

// Strip the chain fields and re-sign, emulating a legacy proof minted before the
// chain existed.
function toLegacy(event: Record<string, unknown>): string {
  const stripped = { ...event };
  delete stripped.entry_index;
  delete stripped.previous_entry_hash;
  return resign(stripped);
}

// Build a 4-entry, fully-chained ledger: prove A, B, then refresh A, B.
function buildChainedLedger(ws: Workspace): void {
  bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
  bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
  proveOne(ws, ROW_A, false);
  proveOne(ws, ROW_B, false);
  proveOne(ws, ROW_A, true);
  proveOne(ws, ROW_B, true);
  expect(readLines(ws)).toHaveLength(4);
}

function validate(ws: Workspace) {
  return runValidateLedgerCommand({
    context: ws.context,
    evidencePath: ws.evidencePath,
    bindingsPath: ws.bindingsPath,
    publicKeyResolver: resolver
  });
}

function codes(result: ReturnType<typeof validate>): string[] {
  return result.errors.map((error) => error.code);
}

describe("validate-ledger verifies the tamper-evident hash chain", () => {
  test("a valid chained ledger verifies ok", () => {
    const ws = makeWorkspace();
    buildChainedLedger(ws);

    const result = validate(ws);
    expect(result.exit_code).toBe(0);
    expect(result.ok).toBe(true);
    expect(result.chain.ok).toBe(true);
    expect(result.chain.verified_entries).toBe(4);
    expect(result.chain.legacy_prefix_count).toBe(0);
  });

  test("editing a chained entry's body fails with the chain-broken code", () => {
    const ws = makeWorkspace();
    buildChainedLedger(ws);

    // Edit a MIDDLE entry's body (created_at) and re-sign so the signature stays
    // valid — the only thing that fails is the NEXT entry's chain link.
    const lines = readLines(ws);
    const middle = parse(lines[1]);
    middle.created_at = "2026-06-28T23:59:59.000Z";
    lines[1] = resign(middle);
    writeLines(ws, lines);

    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.ok).toBe(false);
    expect(result.chain.ok).toBe(false);
    expect(codes(result)).toContain("UCM_LEDGER_CHAIN_BROKEN");
  });

  test("reordering two chained entries fails", () => {
    const ws = makeWorkspace();
    buildChainedLedger(ws);

    const lines = readLines(ws);
    [lines[1], lines[2]] = [lines[2], lines[1]];
    writeLines(ws, lines);

    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.chain.ok).toBe(false);
    expect(codes(result)).toContain("UCM_LEDGER_INDEX_GAP");
  });

  test("truncating a middle chained entry fails", () => {
    const ws = makeWorkspace();
    buildChainedLedger(ws);

    const lines = readLines(ws);
    lines.splice(2, 1); // remove the entry at position 2
    writeLines(ws, lines);

    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.chain.ok).toBe(false);
    expect(codes(result)).toContain("UCM_LEDGER_CHAIN_BROKEN");
  });

  test("a duplicate entry_index fails", () => {
    const ws = makeWorkspace();
    buildChainedLedger(ws);

    const lines = readLines(ws);
    lines.splice(2, 0, lines[1]); // duplicate the entry at position 1
    writeLines(ws, lines);

    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.chain.ok).toBe(false);
    expect(codes(result)).toContain("UCM_LEDGER_DUPLICATE_INDEX");
  });
});

describe("validate-ledger is backward compatible with legacy un-chained ledgers", () => {
  test("a legacy-only ledger (no chain fields) still validates ok", () => {
    const ws = makeWorkspace();
    buildChainedLedger(ws);

    // Strip chain fields from every entry (and re-sign) -> a purely-legacy ledger.
    const lines = readLines(ws).map((line) => toLegacy(parse(line)));
    writeLines(ws, lines);

    const result = validate(ws);
    expect(result.exit_code).toBe(0);
    expect(result.ok).toBe(true);
    expect(result.chain.ok).toBe(true);
    expect(result.chain.verified_entries).toBe(0);
    expect(result.chain.legacy_prefix_count).toBe(4);
  });

  test("a legacy-prefix-then-chained ledger verifies the suffix and reports the prefix", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");

    // First mint two proofs, then DOWNGRADE them to legacy (strip chain + resign)
    // so the ledger opens with a 2-entry un-chained prefix on disk.
    proveOne(ws, ROW_A, false);
    proveOne(ws, ROW_B, false);
    const legacy = readLines(ws).map((line) => toLegacy(parse(line)));
    writeLines(ws, legacy);
    expect(readLines(ws)).toHaveLength(2);

    // Now prove onto the legacy prefix: prove reads the tail and chains the new
    // entries onto the last LEGACY entry (the chain starts mid-ledger).
    proveOne(ws, ROW_A, true);
    proveOne(ws, ROW_B, true);
    expect(readLines(ws)).toHaveLength(4);

    const result = validate(ws);
    expect(result.exit_code).toBe(0);
    expect(result.ok).toBe(true);
    expect(result.chain.ok).toBe(true);
    expect(result.chain.legacy_prefix_count).toBe(2);
    expect(result.chain.verified_entries).toBe(2);

    // Sanity: the suffix really is chained.
    const lines = readLines(ws).map(parse);
    expect(lines[0].entry_index).toBeUndefined();
    expect(lines[1].entry_index).toBeUndefined();
    expect(lines[2].entry_index as number).toBe(2);
    expect(lines[3].entry_index as number).toBe(3);
  });
});
