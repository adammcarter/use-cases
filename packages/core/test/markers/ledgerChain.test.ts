// PIECE 1 (v1 tamper-evident ledger): `prove` emits a hash-chain on every new
// proof event. Each appended entry carries an absolute `entry_index` and the
// `previous_entry_hash` (the sha256 of the previous entry's full canonical JSON,
// or the genesis sentinel for the first entry). Because the chain fields live
// INSIDE the event before signing, the signature covers them (tamper-evident).
//
// The fields are ADDITIVE / NON-BREAKING: legacy proof events that predate the
// chain (no entry_index / previous_entry_hash) must still validate against the
// now-optional schema and must still reach FRESH via scan.
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  GENESIS_ENTRY_HASH,
  computeLedgerEntryHash,
  runBindCommand,
  runProveCommand,
  runScanCommand,
  runVerifyCommand,
  signEvent,
  singleKeyResolver,
  validateProofEvent,
  verifyEvent,
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
  const root = mkdtempSync(join(tmpdir(), "ucm-ledger-chain-"));
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

function mintResults(
  ws: Workspace,
  opts: { all?: boolean; rowId?: string } = { all: true }
): VerificationResultRecord[] {
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

function readEvents(ws: Workspace): ProofEvent[] {
  return readFileSync(ws.evidencePath, "utf8")
    .trim()
    .split("\n")
    .filter((line) => line.trim() !== "")
    .map((line) => JSON.parse(line) as ProofEvent);
}

function scanFor(ws: Workspace, rowId: string): string {
  const result = runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode: "feature" as const,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
  const row = result.status.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} missing from status`);
  }
  return row.status;
}

describe("prove emits a tamper-evident hash chain", () => {
  test("the first proof on an empty ledger carries index 0 and the genesis sentinel", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });

    const result = runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: results
    });
    expect(result.exit_code).toBe(0);

    const [first] = readEvents(ws);
    expect(first.entry_index).toBe(0);
    expect(first.previous_entry_hash).toBe(GENESIS_ENTRY_HASH);
    expect(GENESIS_ENTRY_HASH).toBe(`sha256:${"0".repeat(64)}`);
  });

  test("a second proof chains to the first (previous_entry_hash == hash of entry 0)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });

    runProveCommand({ ...proveBase(ws), rowId: ROW_A, trustedCi: true, verificationResults: results });
    // --refresh appends a second proof for the same row.
    runProveCommand({
      ...proveBase(ws),
      rowId: ROW_A,
      trustedCi: true,
      refresh: true,
      verificationResults: results
    });

    const events = readEvents(ws);
    expect(events).toHaveLength(2);
    expect(events[1].entry_index).toBe(1);
    expect(events[1].previous_entry_hash).toBe(computeLedgerEntryHash(events[0]));
  });

  test("a multi-row --all run chains entries sequentially", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    const results = mintResults(ws, { all: true });

    const result = runProveCommand({
      ...proveBase(ws),
      all: true,
      trustedCi: true,
      verificationResults: results
    });
    expect(result.exit_code).toBe(0);
    expect(result.proof_events_appended).toBe(2);

    const events = readEvents(ws);
    expect(events).toHaveLength(2);
    expect(events[0].entry_index).toBe(0);
    expect(events[0].previous_entry_hash).toBe(GENESIS_ENTRY_HASH);
    expect(events[1].entry_index).toBe(1);
    expect(events[1].previous_entry_hash).toBe(computeLedgerEntryHash(events[0]));
  });

  test("the signature verifies over the chained event (chain fields are signed)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });

    runProveCommand({ ...proveBase(ws), rowId: ROW_A, trustedCi: true, verificationResults: results });
    const [event] = readEvents(ws);

    // The signed event verifies as-is.
    expect(verifyEvent(event as unknown as Record<string, unknown>, resolver).ok).toBe(true);
    // Tampering with a chain field breaks the signature (tamper-evident).
    const tampered = { ...event, entry_index: 99 };
    expect(verifyEvent(tampered as unknown as Record<string, unknown>, resolver).ok).toBe(false);
  });

  test("a chained event validates against the proof-event schema", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });
    runProveCommand({ ...proveBase(ws), rowId: ROW_A, trustedCi: true, verificationResults: results });
    const [event] = readEvents(ws);
    expect(validateProofEvent(event).ok).toBe(true);
  });
});

describe("legacy un-chained proofs remain valid (additive / non-breaking)", () => {
  test("a proof WITHOUT chain fields still validates against the schema and still reaches FRESH", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const results = mintResults(ws, { rowId: ROW_A });
    runProveCommand({ ...proveBase(ws), rowId: ROW_A, trustedCi: true, verificationResults: results });

    // Strip the chain fields and re-sign with the same trusted key to emulate a
    // legacy proof that predates the chain.
    const [chained] = readEvents(ws);
    const stripped: Record<string, unknown> = { ...chained };
    delete stripped.entry_index;
    delete stripped.previous_entry_hash;
    delete stripped.signature;
    const legacy = signEvent(stripped, PRIVATE_KEY, KEY_ID);
    expect((legacy as Record<string, unknown>).entry_index).toBeUndefined();
    expect((legacy as Record<string, unknown>).previous_entry_hash).toBeUndefined();
    writeFileSync(ws.evidencePath, `${JSON.stringify(legacy)}\n`);

    // Schema still accepts it (chain fields are optional, not required).
    expect(validateProofEvent(legacy).ok).toBe(true);
    // And the row is still FRESH — chain fields don't affect content hashes.
    expect(scanFor(ws, ROW_A)).toBe("FRESH");
  });
});
