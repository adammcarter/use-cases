import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import { resolveWorkspaceContext } from "../../src/index.js";
import {
  runBindCommand,
  runScanCommand,
  runVerifyCommand,
  singleKeyResolver,
  type VerifySpawnRequest,
  type VerifySpawnResult,
  type VerifySpawnRunner
} from "../../src/markers/index.js";
import { join as pathJoin } from "node:path";
import { generateKeyPairSync } from "node:crypto";

// Increment 4 (variant parametrization): verify treats each variant as its own row.
// ONE spawn per declared variant, each spawn's exit code is that variant's verdict,
// and each result record carries the variant's key + its own distinct hashes. A
// variant family whose command can't distinguish variants ({variant} missing) is a
// surfaced spec error that spawns nothing for that family. See DESIGN.md §4, §9.

const GENERATED_AT = "2026-06-28T12:10:00.000Z";
const resolver = singleKeyResolver(generateKeyPairSync("ed25519").publicKey);
const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) rmSync(dir, { recursive: true, force: true });
  }
});

const CONFIG_YAML = [
  "schema_version: 1",
  "workspace_id: variant.verify.fixture",
  "data_root: .",
  "use_cases_dir: use-cases",
  "evidence_dir: evidence",
  "demo_capsules_dir: demo-capsules",
  "showcase_runs_dir: showcase-runs",
  "component_id: variant-verify",
  "default_workflow_mode: continuous",
  ""
].join("\n");

const SWIFT = `import Foundation

@MainActor
public func cartQuantity(_ n: Int) async throws -> Int {
    return n
}
`;

function familyYaml(command: string[], variantKeys: string[]): string {
  const lines = [
    "schema_version: 1",
    "feature:",
    "  id: cart",
    "  name: Cart",
    "  summary: Cart quantity handling.",
    "use_cases:",
    "  - id: cart.quantity",
    "    title: Cart quantity across shapes",
    "    lifecycle: active",
    "    value_tier: critical",
    "    journey_role: golden",
    "    usage_frequency: common",
    "    actor: shopper",
    "    intent: Set a quantity.",
    "    preconditions: [Cart exists.]",
    "    trigger: Shopper sets a quantity.",
    "    scenarios:",
    "      - id: cart.quantity.web",
    "        kind: steps",
    "        steps: [Set a quantity.]",
    "    observable_outcomes: [The cart reflects the quantity.]",
    "    host_applicability:",
    "      - host_surface: codex.cli",
    "        supported: true",
    "    verification_policy:",
    "      mode: requirements",
    "      verifiers:",
    "        journey:",
    "          kind: script",
    "          evidence_kind: live_demo",
    `          command: [${command.map((part) => JSON.stringify(part)).join(", ")}]`,
    "          inputs: []",
    "      requirements:",
    "        - evidence_kind: live_demo",
    "          required_verifiers: [journey]",
    "          minimum_count: 1",
    "    approval_policy:",
    "      mode: none",
    "    variants:"
  ];
  for (const key of variantKeys) {
    lines.push(`      - key: ${key}`);
  }
  lines.push("");
  return lines.join("\n");
}

function makeWorkspace(command: string[], variantKeys: string[]) {
  const root = mkdtempSync(join(tmpdir(), "uc-verify-variants-"));
  tempDirs.push(root);
  const write = (rel: string, body: string) => {
    const full = join(root, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, body);
  };
  write("use-cases.yml", CONFIG_YAML);
  write("use-cases/cart.yml", familyYaml(command, variantKeys));
  write("Sources/Cart/CartService.swift", SWIFT);
  const context = resolveWorkspaceContext({ workspaceRoot: root });
  return {
    context,
    productRoot: context.workspace_root,
    bindingsPath: join(context.data_root, ".use-cases", "bindings.jsonl"),
    evidencePath: join(context.data_root, ".use-cases", "proofs.jsonl")
  };
}

let idCounter = 0;
function makeId() {
  return () => `01JBIND${String(idCounter++).padStart(19, "0")}`;
}

// The code slug IS the family: bind the family ONCE. Its variants share this span.
function bindFamily(ws: ReturnType<typeof makeWorkspace>): void {
  runBindCommand({
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    rowId: "cart.quantity",
    file: "Sources/Cart/CartService.swift",
    mode: "swift-func",
    line: 3,
    clock: () => GENERATED_AT,
    idFactory: makeId()
  });
}

function verifyBase(ws: ReturnType<typeof makeWorkspace>) {
  return {
    context: ws.context,
    productRoot: ws.productRoot,
    bindingsPath: ws.bindingsPath,
    evidencePath: ws.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  };
}

// A spawn spy that records every command it was asked to run and returns a verdict
// keyed by the variant token found in the command (so a test can fail one variant).
function spySpawn(failVariants: string[] = []): { runner: VerifySpawnRunner; calls: string[][] } {
  const calls: string[][] = [];
  const runner: VerifySpawnRunner = (request: VerifySpawnRequest): VerifySpawnResult => {
    calls.push(request.command);
    const failed = failVariants.some((variant) => request.command.includes(variant));
    return { exit_code: failed ? 1 : 0, timed_out: false, stdout: "", stderr: "" };
  };
  return { runner, calls };
}

describe("verify — variant families (increment 4)", () => {
  test("one spawn per variant, one record per variant, each with its key", () => {
    const ws = makeWorkspace(["echo", "{variant}"], ["zero", "one", "many"]);
    bindFamily(ws);

    const spy = spySpawn();
    const result = runVerifyCommand({ ...verifyBase(ws), all: true, spawnRunner: spy.runner });

    // One spawn per variant, each with the variant token substituted.
    expect(spy.calls).toHaveLength(3);
    expect(spy.calls.map((cmd) => cmd[cmd.length - 1]).sort()).toEqual(["many", "one", "zero"]);

    // One record per variant row, each carrying its key and a pass verdict.
    const byRow = new Map(result.results.map((r) => [r.row_id, r]));
    expect([...byRow.keys()].sort()).toEqual([
      "cart.quantity::many",
      "cart.quantity::one",
      "cart.quantity::zero"
    ]);
    expect(byRow.get("cart.quantity::zero")?.variant_key).toBe("zero");
    expect(result.results.every((r) => r.status === "pass")).toBe(true);

    // Per-variant integrity: distinct row + binding-set hashes.
    const rowHashes = new Set(result.results.map((r) => r.row_hash));
    const bindHashes = new Set(result.results.map((r) => r.binding_set_hash));
    expect(rowHashes.size).toBe(3);
    expect(bindHashes.size).toBe(3);
  });

  test("exit code is each variant's verdict (partial fail)", () => {
    const ws = makeWorkspace(["echo", "{variant}"], ["zero", "one", "negative"]);
    bindFamily(ws);

    const spy = spySpawn(["negative"]);
    const result = runVerifyCommand({ ...verifyBase(ws), all: true, spawnRunner: spy.runner });

    const byRow = new Map(result.results.map((r) => [r.row_id, r.status]));
    expect(byRow.get("cart.quantity::zero")).toBe("pass");
    expect(byRow.get("cart.quantity::one")).toBe("pass");
    expect(byRow.get("cart.quantity::negative")).toBe("fail");
    // A partial failure is a non-zero overall exit.
    expect(result.exit_code).not.toBe(0);
  });

  test("a variant family whose command lacks {variant} is a spec error (no spawn)", () => {
    const ws = makeWorkspace(["echo", "static"], ["a", "b"]);
    bindFamily(ws);

    const spy = spySpawn();
    const result = runVerifyCommand({ ...verifyBase(ws), all: true, spawnRunner: spy.runner });

    // Nothing ran — the command can't distinguish variants.
    expect(spy.calls).toHaveLength(0);
    expect(result.results.every((r) => r.status !== "pass")).toBe(true);
    expect(result.errors.some((e) => e.code === "VARIANT_TOKEN_MISSING")).toBe(true);
  });
});

describe("scan — variant family local status (increment 6)", () => {
  function scanBase(ws: ReturnType<typeof makeWorkspace>) {
    return {
      context: ws.context,
      productRoot: ws.productRoot,
      bindingsPath: ws.bindingsPath,
      evidencePath: ws.evidencePath,
      publicKeyResolver: resolver,
      policyMode: "feature" as const,
      generatedAt: GENERATED_AT,
      repoCwd: ws.context.workspace_root
    };
  }

  function familyRow(ws: ReturnType<typeof makeWorkspace>) {
    const scan = runScanCommand(scanBase(ws));
    return scan.status.rows.find((row) => row.row_id === "cart.quantity");
  }

  const ledger = (ws: ReturnType<typeof makeWorkspace>) =>
    pathJoin(ws.context.data_root, ".use-cases", "verification-results.jsonl");

  test("family is VERIFIED_LOCAL only when EVERY variant passes", () => {
    const ws = makeWorkspace(["echo", "{variant}"], ["zero", "one", "many"]);
    bindFamily(ws);
    runVerifyCommand({ ...verifyBase(ws), all: true, spawnRunner: spySpawn().runner, outPath: ledger(ws) });

    const row = familyRow(ws);
    expect(row?.local_status).toBe("VERIFIED_LOCAL");
    // Breakdown: each variant is green.
    const breakdown = new Map((row?.variant_local_status ?? []).map((v) => [v.key, v.local_status]));
    expect(breakdown.get("zero")).toBe("VERIFIED_LOCAL");
    expect(breakdown.get("many")).toBe("VERIFIED_LOCAL");
  });

  test("one failing variant keeps the family out of VERIFIED_LOCAL and names it", () => {
    const ws = makeWorkspace(["echo", "{variant}"], ["zero", "one", "negative"]);
    bindFamily(ws);
    runVerifyCommand({
      ...verifyBase(ws),
      all: true,
      spawnRunner: spySpawn(["negative"]).runner,
      outPath: ledger(ws)
    });

    const row = familyRow(ws);
    expect(row?.local_status).not.toBe("VERIFIED_LOCAL");
    const breakdown = new Map((row?.variant_local_status ?? []).map((v) => [v.key, v.local_status]));
    expect(breakdown.get("zero")).toBe("VERIFIED_LOCAL");
    expect(breakdown.get("one")).toBe("VERIFIED_LOCAL");
    expect(breakdown.get("negative")).not.toBe("VERIFIED_LOCAL");
  });
});
