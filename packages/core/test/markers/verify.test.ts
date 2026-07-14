import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runProveCommand,
  runScanCommand,
  runVerifyCommand,
  singleKeyResolver,
  type PublicKeyResolver,
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

  // BLOCKER 2b: `verify` RUNS the verifier and never CONSUMES signed proofs, so a
  // missing --public-key is NOT a reason to abort. With a signed proof present but
  // no key to check it, verify still verifies the bound row (exit 0) — it does not
  // fail with LEDGER_INVALID. (A key that REJECTS the signature is different: see
  // the next test.)
  test("a missing --public-key does NOT block verify: the bound row is still verified (exit 0, no LEDGER_INVALID)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");

    // Land one signed proof so the evidence ledger is non-empty and carries a
    // real ed25519 signature.
    const minted = runVerifyCommand({ ...verifyBase(ws), rowId: ROW_A, spawnRunner: passSpawn });
    const proof = runProveCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: minted.results,
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
      generatedAt: GENERATED_AT,
      idFactory: makeId("01JPROVE")
    });
    expect(proof.proof_events_appended).toBe(1);

    // Re-run verify with a resolver that knows NO keys — exactly what happens when
    // the caller forgets `--public-key`. A pure missing-key failure is the keyless
    // path, not corruption: verify RUNS the verifier for the bound row.
    const emptyResolver: PublicKeyResolver = () => undefined;
    const result = runVerifyCommand({
      ...verifyBase(ws),
      publicKeyResolver: emptyResolver,
      trustedKeyConfigured: false,
      all: true,
      spawnRunner: passSpawn
    });

    expect(result.exit_code).toBe(0);
    expect(result.results.map((record) => record.row_id)).toContain(ROW_A);
    expect(result.results.every((record) => record.status === "pass")).toBe(true);
    expect(result.errors.map((error) => error.code)).not.toContain("LEDGER_INVALID");
  });

  // The complement: a key that is PRESENT but REJECTS the proof's signature is
  // REAL corruption (BAD_SIGNATURE), and verify still fails closed (exit 4).
  test("a WRONG --public-key (rejects the signature) still fails closed with LEDGER_INVALID (exit 4)", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const minted = runVerifyCommand({ ...verifyBase(ws), rowId: ROW_A, spawnRunner: passSpawn });
    runProveCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      rowId: ROW_A,
      trustedCi: true,
      verificationResults: minted.results,
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
      generatedAt: GENERATED_AT,
      idFactory: makeId("01JPROVE")
    });

    // A resolver that returns a DIFFERENT key for the same key_id -> BAD_SIGNATURE.
    const wrong = generateKeyPairSync("ed25519");
    const wrongResolver: PublicKeyResolver = singleKeyResolver(wrong.publicKey);
    const result = runVerifyCommand({
      ...verifyBase(ws),
      publicKeyResolver: wrongResolver,
      all: true,
      spawnRunner: passSpawn
    });

    expect(result.exit_code).toBe(4);
    expect(result.errors.map((error) => error.code)).toContain("LEDGER_INVALID");
    expect(result.errors.map((error) => error.code)).toContain("BAD_SIGNATURE");
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

  // Data loss (field report, 0.4.0): --out was written with a truncating write of
  // ONLY the targeted rows, so `verify --row A` erased row B's result from the
  // ledger scan auto-discovers -> every OTHER row silently fell back to
  // UNVERIFIED_LOCAL. Verifying one row must never destroy another row's evidence.
  test("--row merges into the existing ledger and preserves other rows' results", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    bind(ws, ROW_B, "Sources/Checkout/RefundService.swift");
    const outPath = join(ws.productRoot, "verify-results.jsonl");

    // Both rows verified: the ledger holds A and B.
    runVerifyCommand({ ...verifyBase(ws), all: true, outPath, spawnRunner: passSpawn });
    expect(readFileSync(outPath, "utf8").trim().split("\n")).toHaveLength(2);

    // Now verify ONLY row A against the same ledger.
    const single = runVerifyCommand({
      ...verifyBase(ws),
      rowId: ROW_A,
      outPath,
      spawnRunner: passSpawn
    });
    expect(single.exit_code).toBe(0);

    // Row B's result MUST still be on disk — it was never re-run, and nothing
    // about it changed.
    const records = readFileSync(outPath, "utf8")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    expect(records.map((record) => record.row_id).sort()).toEqual([ROW_A, ROW_B]);
  });

  // The merge must REPLACE a row's prior record rather than append a duplicate,
  // so a re-verified row has exactly one (current) result in the ledger.
  test("re-verifying a row replaces its prior record instead of duplicating it", () => {
    const ws = makeWorkspace();
    bind(ws, ROW_A, "Sources/Checkout/CouponService.swift");
    const outPath = join(ws.productRoot, "verify-results.jsonl");

    runVerifyCommand({ ...verifyBase(ws), rowId: ROW_A, outPath, spawnRunner: passSpawn });
    runVerifyCommand({ ...verifyBase(ws), rowId: ROW_A, outPath, spawnRunner: failSpawn });

    const records = readFileSync(outPath, "utf8")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    expect(records).toHaveLength(1);
    // The LATEST run wins: the fail result replaced the earlier pass.
    expect(records[0].row_id).toBe(ROW_A);
    expect(records[0].status).toBe("fail");
  });
});

// ---------------------------------------------------------------------------
// Config-driven verifier resolution: a row whose `acceptance` verifier comes
// from the WORKSPACE config's default (a preset) must produce the SAME
// verification_context_hash in verify, prove, AND scan — so prove embeds it,
// scan re-derives it, and the row reaches FRESH. And with NO config default and
// NO row verifier, `acceptance` is BLOCKED (never silently pnpm/vitest).
// ---------------------------------------------------------------------------

const ROW_PRESET = "checkout.preset_default";

const USE_CASE_ACCEPTANCE_YAML = `schema_version: 1
feature:
  id: checkout
  name: Checkout
  summary: Shoppers can apply coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
  - id: ${ROW_PRESET}
    title: A row whose acceptance verifier comes from workspace config
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
      - id: ${ROW_PRESET}.web
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
      requirements:
        - evidence_kind: test_result
          required_verifiers: [acceptance]
          minimum_count: 1
    approval_policy:
      mode: none
`;

const CONFIG_WITH_DEFAULT_YAML = `schema_version: 1
workspace_id: markers.fixture
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
component_id: presentation-skills
default_workflow_mode: continuous
verifiers:
  default: acceptance
  acceptance:
    preset: js.vitest
`;

const SWIFT_PRESET = `import Foundation

@MainActor
public func presetDefault(_ code: String) async throws -> Int {
    return 7
}
`;

function makeCustomWorkspace(configYaml: string): Workspace {
  const root = mkdtempSync(join(tmpdir(), "ucm-verify-cfg-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", configYaml);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_ACCEPTANCE_YAML);
  writeFile(root, "Sources/Checkout/PresetService.swift", SWIFT_PRESET);
  // The js.vitest preset declares this acceptance test as an input.
  writeFile(root, `tests/use-cases/${ROW_PRESET}.test.ts`, "// the acceptance test\n");
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl"),
    context
  };
}

function scanStatus(ws: Workspace, rowId: string): string {
  const result = runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode: "feature",
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
  const row = result.status.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} missing from status`);
  }
  return row.status;
}

describe("config-driven verifier resolution (verify/prove/scan agreement)", () => {
  test("a config-default preset verifier yields ONE context hash across verify, prove, and scan => FRESH", () => {
    const ws = makeCustomWorkspace(CONFIG_WITH_DEFAULT_YAML);
    bind(ws, ROW_PRESET, "Sources/Checkout/PresetService.swift");

    // verify resolves `acceptance` via the workspace config default (a preset),
    // runs it (injected pass), and stamps a context hash.
    const verifyResult = runVerifyCommand({
      ...verifyBase(ws),
      rowId: ROW_PRESET,
      spawnRunner: passSpawn
    });
    expect(verifyResult.results).toHaveLength(1);
    const record = verifyResult.results[0];
    expect(record.status).toBe("pass");
    expect(record.verifier_id).toBe("acceptance");
    const verifyHash: string = record.verification_context_hash;

    // prove CONSUMES that result and embeds the SAME context hash in the proof.
    const proof = runProveCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      rowId: ROW_PRESET,
      trustedCi: true,
      verificationResults: verifyResult.results,
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
      generatedAt: GENERATED_AT,
      idFactory: makeId("01JPROVE")
    });
    expect(proof.proof_events_appended).toBe(1);
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    const embeddedHash: string = event.verification.context_hash;
    expect(embeddedHash).toBe(verifyHash);

    // scan RE-DERIVES the context hash with the same config; matching => FRESH.
    expect(scanStatus(ws, ROW_PRESET)).toBe("FRESH");
  });

  test("with NO config default and NO row verifier, `acceptance` is BLOCKED (not silently pnpm/vitest)", () => {
    const ws = makeCustomWorkspace(CONFIG_YAML); // base config has no verifiers section
    bind(ws, ROW_PRESET, "Sources/Checkout/PresetService.swift");

    const verifyResult = runVerifyCommand({
      ...verifyBase(ws),
      rowId: ROW_PRESET,
      spawnRunner: passSpawn
    });
    expect(verifyResult.exit_code).not.toBe(0);
    expect(verifyResult.results).toHaveLength(1);
    expect(verifyResult.results[0].status).toBe("blocked");
    expect(verifyResult.results[0].verifier_id).toBe("acceptance");

    // prove cannot certify a blocked verification.
    const proof = runProveCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      rowId: ROW_PRESET,
      trustedCi: true,
      verificationResults: verifyResult.results,
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
      generatedAt: GENERATED_AT,
      idFactory: makeId("01JPROVE")
    });
    expect(proof.exit_code).toBe(5);
    expect(proof.rows[0].status).toBe("failed");
    expect(proof.rows[0].reason).toBe("RESULT_BLOCKED");
  });
});
