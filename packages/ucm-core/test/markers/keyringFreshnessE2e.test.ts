// End-to-end keyring trust flow: prove -> scan, resolving proof signatures via an
// opt-in multi-key keyring (schemas/v1/keyring.schema.json) instead of the single
// --public-key path. This mirrors cli.test.ts acceptance 6 ("prove then scan =>
// FRESH"), but the public key is resolved through a keyring file, so the test
// proves revocation and rotation are honoured through the FULL pipeline:
//
//   * an ACTIVE, in-window key verifies the proof it signed       -> row FRESH
//   * the SAME proof, once its key is REVOKED in the keyring       -> row NOT FRESH
//   * the SAME proof, once its key's window has EXPIRED            -> row NOT FRESH
//   * rotation: add a new active key + re-prove under it           -> row FRESH again
//
// Fail-closed end to end: when the keyring will not vouch for the signing key at
// the proof's created_at, scan finds no verifiable matching proof and the row
// falls to UNPROVEN (never FRESH). The append-only ledger is real on-disk JSONL
// and the keyring is a real on-disk file loaded via keyringPublicKeyResolverFromFile.
import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { mkdirSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  keyringPublicKeyResolverFromFile,
  runBindCommand,
  runProveCommand,
  runScanCommand,
  singleKeyResolver,
  type Keyring,
  type ProveCommandOptions
} from "../../src/markers/index.js";

const ALLOW_UNSAFE_ENV = "UCM_ALLOW_UNSAFE_VERIFICATION";

const ROW_ID = "checkout.apply_coupon";
// Proofs are minted with this created_at; the keyring windows are anchored around it.
const GENERATED_AT = "2026-06-28T12:10:00.000Z";
// A later moment used when re-proving during rotation, so the new proof is
// unambiguously the newest (byNewest) and the keyring window still covers it.
const ROTATED_AT = "2026-06-28T13:00:00.000Z";

const USE_CASE_YAML = `schema_version: 1
feature:
  id: checkout
  name: Checkout
  summary: Shoppers can apply coupons during checkout.
metadata:
  owner: product
  lifecycle: active
use_cases:
  - id: ${ROW_ID}
    title: Apply a valid coupon
    lifecycle: active
    value_tier: critical
    journey_role: golden
    usage_frequency: common
    actor: shopper
    intent: Apply a valid coupon to a cart.
    preconditions:
      - A cart exists.
      - A coupon exists.
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${ROW_ID}.web
        kind: steps
        steps:
          - The shopper submits a coupon code.
          - The system applies the discount.
    observable_outcomes:
      - The cart total reflects the discount.
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: requirements
      requirements:
        - evidence_kind: live_demo
          required_verifiers: [user]
          minimum_count: 1
    approval_policy:
      mode: predefined
      requirements:
        - approver_type: user
          minimum_count: 1
      statement: Final acceptance requires user-visible proof.
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

const SWIFT_FUNC_SOURCE = `import Foundation

@MainActor
public func applyCoupon(_ code: String) async throws -> Int {
    return 1
}
`;

// Two independent ed25519 keypairs: key A is the original CI signer, key B is the
// rotated-in successor. Private keys sign proofs; PEM public keys go in the keyring.
interface Pair {
  privateKey: KeyObject;
  publicKeyPem: string;
}
function ed25519Pair(): Pair {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return { privateKey, publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString() };
}

const KEY_A = ed25519Pair();
const KEY_B = ed25519Pair();
const KEY_ID_A = "ci-key-1";
const KEY_ID_B = "ci-key-2";

const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

// The unsafe-assume seam needs the env var; set it for the file (it only activates
// when a test passes `unsafeAssumeVerificationResult`).
let previousUnsafe: string | undefined;
beforeEach(() => {
  previousUnsafe = process.env[ALLOW_UNSAFE_ENV];
  process.env[ALLOW_UNSAFE_ENV] = "1";
});
afterEach(() => {
  if (previousUnsafe === undefined) {
    delete process.env[ALLOW_UNSAFE_ENV];
  } else {
    process.env[ALLOW_UNSAFE_ENV] = previousUnsafe;
  }
});

interface Workspace {
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  keyringDir: string;
  context: ReturnType<typeof resolveWorkspaceContext>;
}

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

function makeWorkspace(): Workspace {
  const root = mkdtempSync(join(tmpdir(), "ucm-keyring-e2e-"));
  tempDirs.push(root);
  writeFile(root, "presentation-skills.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "Sources/Checkout/CouponService.swift", SWIFT_FUNC_SOURCE);
  const keyringDir = mkdtempSync(join(tmpdir(), "ucm-keyring-files-"));
  tempDirs.push(keyringDir);
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "evidence.jsonl"),
    keyringDir,
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
    rowId: ROW_ID,
    file: "Sources/Checkout/CouponService.swift",
    mode: "swift-func",
    line: 3,
    clock: () => GENERATED_AT,
    idFactory: makeId("01JBIND")
  });
  expect(result.exit_code).toBe(0);
}

// Mint a signed proof for ROW_ID under the given key. `resolver` is what prove
// uses to validate the EXISTING ledger before appending; it must vouch for every
// proof already on disk (a revoked old proof would block the append, exit 4).
function prove(
  ws: Workspace,
  signer: Pair,
  keyId: string,
  resolver: ProveCommandOptions["publicKeyResolver"],
  options: { refresh?: boolean; generatedAt?: string } = {}
): ReturnType<typeof runProveCommand> {
  return runProveCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    rowId: ROW_ID,
    generatedAt: options.generatedAt ?? GENERATED_AT,
    idFactory: makeId("01JPROVE"),
    trustedCi: true,
    refresh: options.refresh ?? false,
    unsafeAssumeVerificationResult: "pass",
    signingKey: { privateKey: signer.privateKey, keyId }
  });
}

// Write a keyring file and return a resolver over it (exercises load + parse +
// schema-validate + window/status enforcement, end to end).
function keyringResolverFile(ws: Workspace, name: string, keyring: Keyring) {
  const path = join(ws.keyringDir, name);
  writeFileSync(path, JSON.stringify(keyring), "utf8");
  return keyringPublicKeyResolverFromFile(path);
}

function keyEntry(
  keyId: string,
  publicKeyPem: string,
  status: "active" | "revoked",
  validFrom = "2026-01-01T00:00:00Z",
  validUntil: string | null = null
): Keyring["keys"][number] {
  return { key_id: keyId, algorithm: "ed25519", public_key: publicKeyPem, valid_from: validFrom, valid_until: validUntil, status };
}

function keyring(keys: Keyring["keys"]): Keyring {
  return { keyring_schema_id: "ucase-public-key-registry-v1", keys };
}

function scan(ws: Workspace, resolver: ProveCommandOptions["publicKeyResolver"]) {
  return runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode: "feature",
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
}

function rowStatus(result: ReturnType<typeof runScanCommand>): string {
  const row = result.status.rows.find((entry) => entry.row_id === ROW_ID);
  if (!row) {
    throw new Error(`row ${ROW_ID} missing from scan status`);
  }
  return row.status;
}

describe("keyring end-to-end: revocation + rotation honoured through prove -> scan", () => {
  test("a proof verified via an ACTIVE, in-window keyring key is FRESH", () => {
    const ws = makeWorkspace();
    bind(ws);
    const active = keyringResolverFile(ws, "active.json", keyring([keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "active")]));
    expect(prove(ws, KEY_A, KEY_ID_A, active).proof_events_appended).toBe(1);

    const result = scan(ws, active);
    expect(rowStatus(result)).toBe("FRESH");
    expect(result.status.guard_ok).toBe(true);
  });

  test("the SAME proof is NOT FRESH once its signing key is REVOKED in the keyring", () => {
    const ws = makeWorkspace();
    bind(ws);
    const active = keyringResolverFile(ws, "active.json", keyring([keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "active")]));
    expect(prove(ws, KEY_A, KEY_ID_A, active).proof_events_appended).toBe(1);
    // Sanity: with the active keyring the row is FRESH.
    expect(rowStatus(scan(ws, active))).toBe("FRESH");

    // Flip the very same key to revoked: the proof no longer verifies.
    const revoked = keyringResolverFile(ws, "revoked.json", keyring([keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "revoked")]));
    const result = scan(ws, revoked);
    expect(rowStatus(result)).not.toBe("FRESH");
    // The row's only proof is unverifiable, so it drops to "no verifiable proof" = UNPROVEN.
    expect(rowStatus(result)).toBe("UNPROVEN");
    // Fail-closed: the unverifiable proof is a ledger-integrity error -> guard down.
    expect(result.status.guard_ok).toBe(false);
  });

  test("the SAME proof is NOT FRESH once its key's validity window has EXPIRED", () => {
    const ws = makeWorkspace();
    bind(ws);
    const active = keyringResolverFile(ws, "active.json", keyring([keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "active")]));
    expect(prove(ws, KEY_A, KEY_ID_A, active).proof_events_appended).toBe(1);

    // Active status, but the window closed in March — before the June proof.
    const expired = keyringResolverFile(
      ws,
      "expired.json",
      keyring([keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "active", "2026-01-01T00:00:00Z", "2026-03-01T00:00:00Z")])
    );
    expect(rowStatus(scan(ws, expired))).toBe("UNPROVEN");
  });

  test("ROTATION: add a new active key, re-prove under it, and the row is FRESH again", () => {
    const ws = makeWorkspace();
    bind(ws);

    // 1) Mint under key A; with A active the row is FRESH.
    const onlyA = keyringResolverFile(ws, "only-a.json", keyring([keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "active")]));
    expect(prove(ws, KEY_A, KEY_ID_A, onlyA).proof_events_appended).toBe(1);
    expect(rowStatus(scan(ws, onlyA))).toBe("FRESH");

    // 2) Operator simulates "what if A were revoked?" — the row drops out of FRESH.
    const revokedA = keyringResolverFile(ws, "revoked-a.json", keyring([keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "revoked")]));
    expect(rowStatus(scan(ws, revokedA))).not.toBe("FRESH");

    // 3) Rotate: add B as a new active key, KEEP A active so the existing proof
    //    still validates, then re-prove under B (a fresh proof minted by the
    //    current key). Re-prove needs --refresh because the row is already FRESH.
    const bothActive = keyringResolverFile(
      ws,
      "both-active.json",
      keyring([
        keyEntry(KEY_ID_A, KEY_A.publicKeyPem, "active"),
        keyEntry(KEY_ID_B, KEY_B.publicKeyPem, "active")
      ])
    );
    const rotated = prove(ws, KEY_B, KEY_ID_B, bothActive, { refresh: true, generatedAt: ROTATED_AT });
    expect(rotated.exit_code).toBe(0);
    expect(rotated.proof_events_appended).toBe(1);

    // The row is FRESH again, now backed by a current-key (B) proof.
    const afterRotation = scan(ws, bothActive);
    expect(rowStatus(afterRotation)).toBe("FRESH");
    expect(afterRotation.status.guard_ok).toBe(true);
    // The matching proof is the freshly minted B proof (newest wins) — proving the
    // row was re-proved under the rotated-in key, not still resting on A's proof.
    const row = afterRotation.status.rows.find((entry) => entry.row_id === ROW_ID);
    expect(row?.matching_proof_event?.event_id).toBe(rotated.rows[0].event_id);
    expect(row?.matching_proof_event?.created_at).toBe(ROTATED_AT);
  });

  test("BACKWARD COMPAT: the single --public-key (singleKeyResolver) path still reaches FRESH", () => {
    const ws = makeWorkspace();
    bind(ws);
    // Sign + verify through the unchanged single-key resolver (no keyring).
    const single = singleKeyResolver(KEY_A.publicKeyPem);
    expect(prove(ws, KEY_A, "any-key-id", single).proof_events_appended).toBe(1);
    const result = scan(ws, single);
    expect(rowStatus(result)).toBe("FRESH");
    expect(result.status.guard_ok).toBe(true);
  });
});
