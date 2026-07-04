// PIECE 1 (public-v1, Phase 2): CI-neutral provenance authority on a proof event.
//
// prove embeds an OPTIONAL `authority` record INTO the event before signing, so
// the signature covers it. These tests prove:
//   - a supplied authority is embedded verbatim and the signed event still verifies
//   - tampering with the embedded authority breaks the signature (it is signed)
//   - a freshly-proved event carries a schema-valid authority block
//   - a LEGACY proof minted WITHOUT authority still validates + stays FRESH
//     (freshness matches row/binding/context hashes, not provenance)
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  detectCiAuthority,
  runBindCommand,
  runProveCommand,
  runScanCommand,
  runVerifyCommand,
  singleKeyResolver,
  validateProofEvent,
  verifyEvent,
  type CiAuthority,
  type VerificationResultRecord,
  type VerifySpawnRunner
} from "../../src/markers/index.js";

const ROW_A = "checkout.apply_coupon";
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

const keypair = generateKeyPairSync("ed25519");
const PUBLIC_KEY: KeyObject = keypair.publicKey;
const PRIVATE_KEY: KeyObject = keypair.privateKey;
const KEY_ID = "trusted-ci-test";
const resolver = singleKeyResolver(PUBLIC_KEY);

const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) rmSync(dir, { recursive: true, force: true });
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
  const root = mkdtempSync(join(tmpdir(), "ucm-prove-authority-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_A);
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

function bind(ws: Workspace): void {
  const result = runBindCommand({
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
  expect(result.exit_code).toBe(0);
}

const passSpawn: VerifySpawnRunner = () => ({
  exit_code: 0,
  timed_out: false,
  stdout: "ok\n",
  stderr: ""
});

function mintResults(ws: Workspace): VerificationResultRecord[] {
  return runVerifyCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT,
    spawnRunner: passSpawn,
    rowId: ROW_A
  }).results;
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
    signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID },
    rowId: ROW_A,
    trustedCi: true
  };
}

function rowStatus(ws: Workspace): string {
  const result = runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode: "feature" as const,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
  const row = result.status.rows.find((entry) => entry.row_id === ROW_A);
  if (!row) throw new Error("row missing from status");
  return row.status;
}

function readEvent(ws: Workspace): Record<string, unknown> {
  return JSON.parse(readFileSync(ws.evidencePath, "utf8").trim()) as Record<string, unknown>;
}

const SUPPLIED_AUTHORITY: CiAuthority = {
  type: "ci",
  provider: "gitlab-ci",
  repository: "group/project",
  ref: "main",
  commit: "abcabcabcabcabcabcabcabcabcabcabcabcabca",
  run_id: "99887766",
  actor: "gitlab-user",
  protected_ref: true,
  event: "merge_request_event"
};

describe("prove embeds the CI-neutral authority (signed)", () => {
  test("a supplied authority is embedded verbatim and the signed event still verifies", () => {
    const ws = makeWorkspace();
    bind(ws);
    const results = mintResults(ws);

    const result = runProveCommand({
      ...proveBase(ws),
      authority: SUPPLIED_AUTHORITY,
      verificationResults: results
    });
    expect(result.rows[0].status).toBe("signed");

    const event = readEvent(ws);
    expect(event.authority).toEqual(SUPPLIED_AUTHORITY);
    // The GitHub-shaped producer block is still populated exactly as before.
    expect((event.producer as Record<string, unknown>).kind).toBe("trusted-ci-prover");
    // The embedded authority is covered by the signature.
    expect(verifyEvent(event, resolver).ok).toBe(true);
  });

  test("tampering with the embedded authority breaks the signature", () => {
    const ws = makeWorkspace();
    bind(ws);
    const results = mintResults(ws);
    runProveCommand({ ...proveBase(ws), authority: SUPPLIED_AUTHORITY, verificationResults: results });

    const event = readEvent(ws);
    // Mutate the signed authority -> verification must fail (it was signed).
    (event.authority as CiAuthority).actor = "attacker";
    const verdict = verifyEvent(event, resolver);
    expect(verdict.ok).toBe(false);
  });

  test("a freshly-proved event carries a schema-valid authority block", () => {
    const ws = makeWorkspace();
    bind(ws);
    const results = mintResults(ws);
    // Detected authority (auto-detect path) — schema-valid by construction.
    const authority = detectCiAuthority({
      GITHUB_ACTIONS: "true",
      GITHUB_REPOSITORY: "use-cases/use-cases",
      GITHUB_REF: "refs/heads/main",
      GITHUB_SHA: "0123456789abcdef0123456789abcdef01234567",
      GITHUB_RUN_ID: "1234567890",
      GITHUB_ACTOR: "octocat",
      GITHUB_EVENT_NAME: "push"
    });

    runProveCommand({ ...proveBase(ws), authority, verificationResults: results });

    const event = readEvent(ws);
    expect(event.authority).toEqual(authority);
    // The whole proof event (authority included) is schema-valid.
    const validation = validateProofEvent(event);
    expect(validation.ok).toBe(true);
    expect((event.authority as CiAuthority).provider).toBe("github-actions");
  });
});

describe("legacy proof WITHOUT authority", () => {
  test("still validates and stays FRESH (provenance does not affect freshness)", () => {
    const ws = makeWorkspace();
    bind(ws);
    const results = mintResults(ws);

    // No `authority` option -> a legacy-shaped proof with no authority field.
    const result = runProveCommand({ ...proveBase(ws), verificationResults: results });
    expect(result.rows[0].status).toBe("signed");

    const event = readEvent(ws);
    expect(event).not.toHaveProperty("authority");
    expect(validateProofEvent(event).ok).toBe(true);
    expect(verifyEvent(event, resolver).ok).toBe(true);
    expect(rowStatus(ws)).toBe("FRESH");
  });
});
