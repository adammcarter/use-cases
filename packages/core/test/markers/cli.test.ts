import { generateKeyPairSync, type KeyObject } from "node:crypto";
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, statSync, writeFileSync, existsSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runProveCommand,
  runScanCommand,
  runValidateLedgerCommand,
  signEvent,
  singleKeyResolver,
  type ProveCommandOptions,
  type VerificationResultRecord
} from "../../src/markers/index.js";

// prove no longer runs verifiers; it consumes verification-result records. The
// env var that gates prove's dangerous "assume verification passed" seam.
const ALLOW_UNSAFE_ENV = "UCM_ALLOW_UNSAFE_VERIFICATION";

// ---------------------------------------------------------------------------
// Fixtures: an on-disk tmp workspace + a generated ed25519 keypair, so the CLI
// cores run end to end without shelling out to git or a real CI signer.
// ---------------------------------------------------------------------------

const ROW_ID = "checkout.apply_coupon";
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

const EXPLICIT_SOURCE = `import Foundation

func computeTax() -> Int {
    let rate = 1
    return rate
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

// The unsafe-assume seam needs the env var; set it for the whole file (it only
// activates when a test passes `unsafeAssumeVerificationResult`).
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
  context: ReturnType<typeof resolveWorkspaceContext>;
}

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

function makeWorkspace(sourceFiles: Record<string, string> = {}): Workspace {
  const root = mkdtempSync(join(tmpdir(), "cli-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  for (const [relPath, contents] of Object.entries(sourceFiles)) {
    writeFile(root, relPath, contents);
  }
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl"),
    context
  };
}

let idCounter = 0;
function makeClock(): () => string {
  return () => GENERATED_AT;
}
function makeId(prefix: string): () => string {
  return () => `${prefix}${String(idCounter++).padStart(26 - prefix.length, "0")}`;
}

// A status:fail verification-result record for ROW_ID. status:fail means prove
// refuses regardless of hashes, so placeholder hashes are fine here.
function failRecord(rowId: string): VerificationResultRecord {
  return {
    schema: "ucase-verification-result-v1",
    row_id: rowId,
    slug: rowId,
    status: "fail",
    evidence_kind: "test_result",
    verifier_id: "acceptance",
    verifier_kind: "script",
    exit_code: 1,
    row_hash: `sha256:${"0".repeat(64)}`,
    binding_set_hash: `sha256:${"0".repeat(64)}`,
    span_sha256s: [],
    verification_context_hash: `sha256:${"0".repeat(64)}`,
    stdout_sha256: `sha256:${"0".repeat(64)}`,
    stderr_sha256: `sha256:${"0".repeat(64)}`,
    created_at: GENERATED_AT
  };
}

function bindSwiftFunc(ws: Workspace): ReturnType<typeof runBindCommand> {
  return runBindCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    rowId: ROW_ID,
    file: "Sources/Checkout/CouponService.swift",
    mode: "swift-func",
    line: 3,
    clock: makeClock(),
    idFactory: makeId("01JBIND")
  });
}

function scan(ws: Workspace, policyMode: "feature" | "release" = "feature") {
  return runScanCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    policyMode,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
}

function proveBase(ws: Workspace): Omit<ProveCommandOptions, "trustedCi" | "signingKey"> {
  return {
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    rowId: ROW_ID,
    generatedAt: GENERATED_AT,
    idFactory: makeId("01JPROVE")
  };
}

function rowStatus(result: ReturnType<typeof runScanCommand>, rowId: string): string {
  const row = result.status.rows.find((entry) => entry.row_id === rowId);
  if (!row) {
    throw new Error(`row ${rowId} missing from status`);
  }
  return row.status;
}

describe("bind command", () => {
  test("acceptance 1: places an explicit marker (start+end) and appends one registry event", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponRules.swift": EXPLICIT_SOURCE });
    const result = runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      suffix: "tax",
      file: "Sources/Checkout/CouponRules.swift",
      mode: "explicit",
      startLine: 3,
      endLine: 6,
      clock: makeClock(),
      idFactory: makeId("01JBIND")
    });
    expect(result.exit_code).toBe(0);
    expect(result.registry_event_appended).toBe(true);
    expect(result.binding_slug).toBe("checkout.apply_coupon#tax");
    expect(result.scan_result?.extent_kind).toBe("explicit");

    const source = readFileSync(join(ws.productRoot, "Sources/Checkout/CouponRules.swift"), "utf8");
    expect(source).toContain("//: @use-case:checkout.apply_coupon#tax");
    expect(source).toContain("//: @use-case:end checkout.apply_coupon#tax");

    const registry = readFileSync(ws.bindingsPath, "utf8").trim().split("\n");
    expect(registry).toHaveLength(1);
    expect(JSON.parse(registry[0]).binding_slug).toBe("checkout.apply_coupon#tax");
  });

  test("acceptance 2: places an inferred Swift func marker and appends one registry event", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    const result = bindSwiftFunc(ws);
    expect(result.exit_code).toBe(0);
    expect(result.registry_event_appended).toBe(true);
    expect(result.scan_result?.extent_kind).toBe("swift_func_inferred");

    const source = readFileSync(join(ws.productRoot, "Sources/Checkout/CouponService.swift"), "utf8");
    expect(source).toContain("//: @use-case:checkout.apply_coupon\n@MainActor");

    const registry = readFileSync(ws.bindingsPath, "utf8").trim().split("\n");
    expect(registry).toHaveLength(1);
    expect(JSON.parse(registry[0]).row_id).toBe(ROW_ID);

    // A scan of the bound row reports UNPROVEN (registered, no proof yet).
    expect(rowStatus(scan(ws), ROW_ID)).toBe("UNPROVEN");
  });

  test("acceptance 3: bind never writes proofs.jsonl", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    bindSwiftFunc(ws);
    expect(existsSync(ws.evidencePath)).toBe(false);
  });

  test("preserves the executable bit when rewriting an executable source file", () => {
    const HOOK_SOURCE = "#!/bin/sh\necho deploy\necho done\n";
    const hookRel = "hooks/session-start";
    const ws = makeWorkspace({ [hookRel]: HOOK_SOURCE });
    const hookAbs = join(ws.productRoot, hookRel);
    chmodSync(hookAbs, 0o755);

    const result = runBindCommand({
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      rowId: ROW_ID,
      file: hookRel,
      mode: "explicit",
      startLine: 2,
      endLine: 3,
      clock: makeClock(),
      idFactory: makeId("01JBIND")
    });

    expect(result.exit_code).toBe(0);
    const source = readFileSync(hookAbs, "utf8");
    expect(source).toContain("#: @use-case:checkout.apply_coupon");
    expect(statSync(hookAbs).mode & 0o111).not.toBe(0);
  });
});

describe("scan command", () => {
  test("acceptance 4: scan never writes source, registry, or evidence", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    bindSwiftFunc(ws);
    const sourcePath = join(ws.productRoot, "Sources/Checkout/CouponService.swift");
    const sourceBefore = readFileSync(sourcePath, "utf8");
    const registryBefore = readFileSync(ws.bindingsPath, "utf8");

    const result = scan(ws);
    expect(result.exit_code).toBe(0);

    expect(readFileSync(sourcePath, "utf8")).toBe(sourceBefore);
    expect(readFileSync(ws.bindingsPath, "utf8")).toBe(registryBefore);
    expect(existsSync(ws.evidencePath)).toBe(false);
  });
});

describe("prove command", () => {
  test("acceptance 5: prove WITHOUT --trusted-ci does not append to proofs.jsonl", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    bindSwiftFunc(ws);
    const result = runProveCommand({
      ...proveBase(ws),
      trustedCi: false,
      unsafeAssumeVerificationResult: "pass"
    });
    expect(result.exit_code).toBe(0);
    expect(result.rows[0].status).toBe("candidate");
    expect(result.proof_events_appended).toBe(0);
    expect(existsSync(ws.evidencePath)).toBe(false);
  });

  test("acceptance 6: prove WITH --trusted-ci appends one signed proof; scan then reports FRESH", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    bindSwiftFunc(ws);
    const result = runProveCommand({
      ...proveBase(ws),
      trustedCi: true,
      unsafeAssumeVerificationResult: "pass",
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID }
    });
    expect(result.exit_code).toBe(0);
    expect(result.proof_events_appended).toBe(1);
    expect(result.rows[0].event_id).toBeTruthy();

    const evidence = readFileSync(ws.evidencePath, "utf8").trim().split("\n");
    expect(evidence).toHaveLength(1);
    const event = JSON.parse(evidence[0]);
    expect(event.producer.kind).toBe("trusted-ci-prover");
    expect(event.verification.result).toBe("pass");
    // The proof is bound to its verifier context, and that hash is signed.
    expect(event.verification.context_hash_id).toBe("ucase-verification-context-hash-v1");
    expect(event.verification.context_hash).toMatch(/^sha256:[0-9a-f]{64}$/);

    // FRESH only holds because scan re-derives the SAME context hash the proof
    // embedded; if prove and scan disagreed, this row would be SUSPECT.
    expect(rowStatus(scan(ws), ROW_ID)).toBe("FRESH");
  });

  test("acceptance 7: prove on a FAILING verification result does not append (exit 5)", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    bindSwiftFunc(ws);
    const result = runProveCommand({
      ...proveBase(ws),
      trustedCi: true,
      verificationResults: [failRecord(ROW_ID)],
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID }
    });
    expect(result.exit_code).toBe(5);
    expect(result.rows[0].status).toBe("failed");
    expect(result.rows[0].reason).toBe("RESULT_FAILED");
    expect(result.proof_events_appended).toBe(0);
    expect(existsSync(ws.evidencePath)).toBe(false);
  });

  test("an --append without trusted credentials exits 6", () => {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    bindSwiftFunc(ws);
    const result = runProveCommand({
      ...proveBase(ws),
      trustedCi: false,
      append: true,
      unsafeAssumeVerificationResult: "pass"
    });
    expect(result.exit_code).toBe(6);
    expect(existsSync(ws.evidencePath)).toBe(false);
  });
});

describe("validate-ledger command", () => {
  // Produce a real, valid signed proof on disk to tamper with.
  function setupProven(): Workspace {
    const ws = makeWorkspace({ "Sources/Checkout/CouponService.swift": SWIFT_FUNC_SOURCE });
    bindSwiftFunc(ws);
    const result = runProveCommand({
      ...proveBase(ws),
      trustedCi: true,
      unsafeAssumeVerificationResult: "pass",
      signingKey: { privateKey: PRIVATE_KEY, keyId: KEY_ID }
    });
    expect(result.proof_events_appended).toBe(1);
    return ws;
  }

  function validate(ws: Workspace, extra: Partial<Parameters<typeof runValidateLedgerCommand>[0]> = {}) {
    return runValidateLedgerCommand({
      context: ws.context,
      evidencePath: ws.evidencePath,
      bindingsPath: ws.bindingsPath,
      publicKeyResolver: resolver,
      ...extra
    });
  }

  test("a clean ledger validates", () => {
    const ws = setupProven();
    const result = validate(ws);
    expect(result.exit_code).toBe(0);
    expect(result.ok).toBe(true);
    expect(result.proof_events_checked).toBe(1);
    expect(result.registry_events_checked).toBe(1);
  });

  test("detects a bad signature (exit 4)", () => {
    const ws = setupProven();
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    event.signature.value = Buffer.from("not-a-real-signature").toString("base64");
    writeFileSync(ws.evidencePath, `${JSON.stringify(event)}\n`);

    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.evidence_valid).toBe(false);
    expect(result.errors.some((error) => error.code === "BAD_SIGNATURE")).toBe(true);
  });

  test("detects a binding_set_hash mismatch (exit 4)", () => {
    const ws = setupProven();
    const event = JSON.parse(readFileSync(ws.evidencePath, "utf8").trim());
    // Tamper the embedded set hash, then RE-SIGN so the signature is valid but the
    // event is internally inconsistent (INVALID, not merely suspect).
    event.bindings.binding_set_hash = `sha256:${"d".repeat(64)}`;
    const { signature, ...withoutSignature } = event;
    void signature;
    const resigned = signEvent(withoutSignature, PRIVATE_KEY, KEY_ID);
    writeFileSync(ws.evidencePath, `${JSON.stringify(resigned)}\n`);

    const result = validate(ws);
    expect(result.exit_code).toBe(4);
    expect(result.errors.some((error) => error.code === "BINDING_SET_HASH_MISMATCH")).toBe(true);
  });

  test("detects an append-only violation against the base ref (exit 4)", () => {
    const ws = setupProven();
    const current = readFileSync(ws.bindingsPath, "utf8");
    // The base ref's first registry line differs from the current first line:
    // an edit/delete of an existing line, which is forbidden.
    const tamperedBase = `${JSON.stringify({ tampered: "old line" })}\n${current}`;
    const gitRunner = () => tamperedBase;

    const result = validate(ws, { baseRef: "origin/main", gitRunner });
    expect(result.exit_code).toBe(4);
    expect(result.append_only).toBe(false);
    expect(result.errors.some((error) => error.code === "APPEND_ONLY_VIOLATION")).toBe(true);
  });
});
