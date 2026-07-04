// BLOCKER 2 (core semantics) — keyless usage WITHOUT a public key is a NORMAL
// path, not a ledger-integrity error.
//
// The 0.1.0 keyless daily loop (bind -> verify -> scan -> VERIFIED_LOCAL) needs
// no key, no CI, no flags. But once a SIGNED proof lands in the evidence ledger,
// re-running scan/verify WITHOUT --public-key produced a signature error
// (UNKNOWN_KEY_ID) that flipped evidence_valid=false and made both commands exit
// 4 — even though the row is still keyless-green (VERIFIED_LOCAL) and verify does
// not consume signed proofs at all.
//
// The coherent behaviour: a PURE missing-key failure (a signed proof present, no
// key supplied to check it) must NOT be treated as ledger corruption. scan exits
// 0 with the row UNPROVEN/VERIFIED_LOCAL; verify RUNS the bound row's verifier
// (it never needed the key). GENUINE corruption (a supplied key that REJECTS the
// signature, or a malformed/append-violating ledger) still fails closed exit 4.
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync, appendFileSync } from "node:fs";
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

const ROW_A = "checkout.apply_coupon";
const GENERATED_AT = "2026-06-28T12:10:00.000Z";

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

const keypair = generateKeyPairSync("ed25519");
const PUBLIC_KEY: KeyObject = keypair.publicKey;
const PRIVATE_KEY: KeyObject = keypair.privateKey;
const KEY_ID = "trusted-ci-test";
const withKey = singleKeyResolver(PUBLIC_KEY);
const noKey: PublicKeyResolver = () => undefined;
// A resolver that returns the WRONG key -> a real BAD_SIGNATURE (genuine corruption).
const wrongKeypair = generateKeyPairSync("ed25519");
const wrongKey = singleKeyResolver(wrongKeypair.publicKey);

const passSpawn: VerifySpawnRunner = () => ({ exit_code: 0, timed_out: false, stdout: "ok\n", stderr: "" });

const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
});

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

let idCounter = 0;
function makeId(prefix: string): () => string {
  return () => `${prefix}${String(idCounter++).padStart(26 - prefix.length, "0")}`;
}

interface Workspace {
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  context: ReturnType<typeof resolveWorkspaceContext>;
}

// A workspace with ONE bound row that already carries a SIGNED proof (so it is
// FRESH/VERIFIED_LOCAL with the key) and an unsigned verification-results ledger
// (so the keyless VERIFIED_LOCAL tier is live without any key).
function boundWorkspaceWithSignedProof(): Workspace {
  const root = mkdtempSync(join(tmpdir(), "ucm-nokey-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_A);
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  const ws: Workspace = {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl"),
    context
  };
  const bind = runBindCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    rowId: ROW_A,
    file: "Sources/Checkout/CouponService.swift",
    mode: "swift-func",
    line: 3,
    clock: () => GENERATED_AT,
    idFactory: makeId("01JBIND")
  });
  expect(bind.exit_code).toBe(0);
  const base = {
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    generatedAt: GENERATED_AT
  };
  const verified = runVerifyCommand({
    ...base,
    publicKeyResolver: withKey,
    rowId: ROW_A,
    spawnRunner: passSpawn,
    outPath: join(ws.context.data_root, ".use-cases", "verification-results.jsonl")
  });
  expect(verified.exit_code).toBe(0);
  const proof = runProveCommand({
    ...base,
    publicKeyResolver: withKey,
    rowId: ROW_A,
    trustedCi: true,
    verificationResults: verified.results,
    signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
    append: true,
    idFactory: makeId("01JPROVE")
  });
  expect(proof.proof_events_appended).toBe(1);
  return ws;
}

function scanBase(ws: Workspace) {
  return {
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode: "feature" as const,
    generatedAt: GENERATED_AT,
    repoCwd: ws.context.workspace_root
  };
}

describe("BLOCKER 2 — scan without --public-key on a keyless VERIFIED_LOCAL row", () => {
  test("with the key: the row is FRESH/VERIFIED_LOCAL and scan exits 0", () => {
    const ws = boundWorkspaceWithSignedProof();
    const result = runScanCommand({ ...scanBase(ws), publicKeyResolver: withKey });
    expect(result.exit_code).toBe(0);
    expect(result.status.rows[0].status).toBe("FRESH");
  });

  test("WITHOUT the key: keyless usage is normal — scan exits 0 (NOT 4), row reads UNPROVEN/VERIFIED_LOCAL", () => {
    const ws = boundWorkspaceWithSignedProof();
    // No trusted key material configured -> the keyless path.
    const result = runScanCommand({ ...scanBase(ws), publicKeyResolver: noKey, trustedKeyConfigured: false });
    // The row is still on the keyless green light.
    expect(result.status.rows[0].status).toBe("UNPROVEN");
    expect(result.status.rows[0].local_status).toBe("VERIFIED_LOCAL");
    // A missing key is NOT ledger corruption: scan must exit 0 so the green human
    // view is truthful (no green-while-failed).
    expect(result.exit_code).toBe(0);
  });

  test("GENUINE corruption still fails closed: a WRONG key that rejects the signature -> scan exits 4", () => {
    const ws = boundWorkspaceWithSignedProof();
    const result = runScanCommand({ ...scanBase(ws), publicKeyResolver: wrongKey });
    expect(result.exit_code).toBe(4);
    expect(result.evidence_valid).toBe(false);
  });

  test("GENUINE corruption still fails closed even keyless: a malformed evidence line -> scan exits 4", () => {
    const ws = boundWorkspaceWithSignedProof();
    appendFileSync(ws.evidencePath, "{ this is not valid json\n");
    // Even with NO key configured, real corruption (a malformed line) fails closed.
    const result = runScanCommand({ ...scanBase(ws), publicKeyResolver: noKey, trustedKeyConfigured: false });
    expect(result.exit_code).toBe(4);
  });

  test("keyless but a keyring/key IS configured that can't resolve the key (revoked/expired) still fails closed: scan exits 4", () => {
    const ws = boundWorkspaceWithSignedProof();
    // A key WAS configured (trustedKeyConfigured defaults to true) but it does not
    // resolve the proof's key_id -> a real trust decision, not the keyless path.
    const result = runScanCommand({ ...scanBase(ws), publicKeyResolver: noKey });
    expect(result.exit_code).toBe(4);
    expect(result.evidence_valid).toBe(false);
  });
});

describe("BLOCKER 2b — verify runs a bound row WITHOUT --public-key", () => {
  test("verify --row without a key RUNS the verifier for the bound row (no LEDGER_INVALID)", () => {
    const ws = boundWorkspaceWithSignedProof();
    const result = runVerifyCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: noKey,
      trustedKeyConfigured: false,
      generatedAt: GENERATED_AT,
      rowId: ROW_A,
      spawnRunner: passSpawn
    });
    expect(result.results).toHaveLength(1);
    expect(result.results[0].row_id).toBe(ROW_A);
    expect(result.results[0].status).toBe("pass");
    expect(result.exit_code).toBe(0);
    expect(result.errors.map((error) => error.code)).not.toContain("LEDGER_INVALID");
  });

  test("verify --all without a key verifies the bound row (never 'no bound behaviours to verify')", () => {
    const ws = boundWorkspaceWithSignedProof();
    const result = runVerifyCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: noKey,
      trustedKeyConfigured: false,
      generatedAt: GENERATED_AT,
      all: true,
      spawnRunner: passSpawn
    });
    expect(result.results.map((r) => r.row_id)).toContain(ROW_A);
    expect(result.exit_code).toBe(0);
  });

  test("verify still fails closed on GENUINE corruption (a malformed evidence line) -> exit 4", () => {
    const ws = boundWorkspaceWithSignedProof();
    appendFileSync(ws.evidencePath, "{ not json\n");
    const result = runVerifyCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: noKey,
      trustedKeyConfigured: false,
      generatedAt: GENERATED_AT,
      all: true,
      spawnRunner: passSpawn
    });
    expect(result.exit_code).toBe(4);
    expect(result.errors.map((error) => error.code)).toContain("LEDGER_INVALID");
  });
});
