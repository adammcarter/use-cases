import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runProveCommand,
  runVerifyCommand,
  singleKeyResolver,
  type VerifySpawnRunner
} from "../../src/markers/index.js";

// ---------------------------------------------------------------------------
// Fixtures: an on-disk tmp workspace with two bound rows (each declaring a
// script verifier) and one row whose required verifier is undeclared (so it
// resolves to BLOCKED). The spawn runner is injected, so verify never shells
// out — a fake decides pass/fail per-row deterministically.
// ---------------------------------------------------------------------------

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
  const root = mkdtempSync(join(tmpdir(), "ucm-verify-"));
  tempDirs.push(root);
  writeFile(root, "presentation-skills.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_A);
  writeFile(root, "Sources/Checkout/RefundService.swift", SWIFT_B);
  writeFile(root, "Sources/Checkout/ThingService.swift", SWIFT_C);
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "evidence.jsonl"),
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

function verifyBase(ws: Workspace) {
  return {
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  };
}

const passSpawn: VerifySpawnRunner = () => ({
  exit_code: 0,
  timed_out: false,
  stdout: "ok\n",
  stderr: ""
});

const failSpawn: VerifySpawnRunner = () => ({
  exit_code: 1,
  timed_out: false,
  stdout: "",
  stderr: "boom\n"
});

describe("verify command", () => {
  test("a passing verifier emits a status:pass record with all hashes", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const result = runVerifyCommand({ ...verifyBase(ws), rowId: ROW_A, spawnRunner: passSpawn });

    expect(result.exit_code).toBe(0);
    expect(result.results).toHaveLength(1);
    const record = result.results[0];
    expect(record.schema).toBe("ucase-verification-result-v1");
    expect(record.row_id).toBe(ROW_A);
    expect(record.status).toBe("pass");
    expect(record.verifier_id).toBe("coupon_check");
    expect(record.verifier_kind).toBe("script");
    expect(record.evidence_kind).toBe("test_result");
    expect(record.exit_code).toBe(0);
    expect(record.row_hash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(record.binding_set_hash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(record.span_sha256s.length).toBeGreaterThan(0);
    expect(record.span_sha256s[0]).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(record.verification_context_hash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(record.stdout_sha256).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(record.stderr_sha256).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(record.created_at).toBe(GENERATED_AT);
  });

  test("a nonzero exit code yields status:fail and a nonzero command exit", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const result = runVerifyCommand({ ...verifyBase(ws), rowId: ROW_A, spawnRunner: failSpawn });

    expect(result.exit_code).not.toBe(0);
    expect(result.results).toHaveLength(1);
    expect(result.results[0].status).toBe("fail");
    expect(result.results[0].exit_code).toBe(1);
  });

  test("an unresolvable verifier yields status:blocked (recorded, never crashes)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_C, "Sources/Checkout/ThingService.swift");
    const result = runVerifyCommand({ ...verifyBase(ws), rowId: ROW_C, spawnRunner: passSpawn });

    expect(result.exit_code).not.toBe(0);
    expect(result.results).toHaveLength(1);
    expect(result.results[0].status).toBe("blocked");
    expect(result.results[0].verifier_id).toBe("no_such_verifier");
    expect(result.results[0].exit_code).toBeNull();
  });

  test("--all iterates every bound row (sorted by slug)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    // ROW_C is left UNBOUND, so --all must NOT target it.
    const result = runVerifyCommand({ ...verifyBase(ws), all: true, spawnRunner: passSpawn });

    expect(result.exit_code).toBe(0);
    expect(result.results.map((record) => record.row_id)).toEqual([ROW_A, ROW_B]);
    expect(result.results.every((record) => record.status === "pass")).toBe(true);
  });

  test("the emitted record carries the SAME verification_context_hash a trusted proof embeds", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");

    // verify mints the result, then a trusted prove CONSUMES it and embeds the
    // same context hash in the signed proof.
    const result = runVerifyCommand({ ...verifyBase(ws), rowId: ROW_A, spawnRunner: passSpawn });
    const recordHash: string = result.results[0].verification_context_hash;

    const proof = runProveCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: result.results,
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
      generatedAt: GENERATED_AT,
      idFactory: makeId("01JPROVE")
    });
    expect(proof.proof_events_appended).toBe(1);
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    const embeddedContextHash: string = event.verification.context_hash;
    expect(embeddedContextHash).toMatch(/^sha256:[0-9a-f]{64}$/);
    expect(embeddedContextHash).toBe(recordHash);
  });

  test("writes one JSONL record per targeted row to --out", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    const outPath = join(ws.productRoot, "verify-results.jsonl");
    const result = runVerifyCommand({ ...verifyBase(ws), all: true, outPath, spawnRunner: passSpawn });

    expect(result.out_path).toBe(outPath);
    const lines = readFileSync(outPath, "utf8").trim().split("\n");
    expect(lines).toHaveLength(2);
    const records = lines.map((line) => JSON.parse(line));
    expect(records.map((record) => record.row_id)).toEqual([ROW_A, ROW_B]);
    expect(records.every((record) => record.schema === "ucase-verification-result-v1")).toBe(true);
  });
});
