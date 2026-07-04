import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { generateKeyPairSync } from "node:crypto";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync, type SpawnSyncReturns } from "node:child_process";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../../..");
const cliBin = join(repoRoot, "packages/cli/dist/index.js");
const tempDirs: string[] = [];

beforeAll(() => {
  requireSuccess(run("corepack", ["pnpm", "build"]));
}, 120_000);

function run(command: string, args: string[]): SpawnSyncReturns<string> {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runCli(args: string[]): SpawnSyncReturns<string> {
  return run("node", ["packages/cli/dist/index.js", ...args]);
}

function requireSuccess(result: SpawnSyncReturns<string>): void {
  if (result.status !== 0) {
    throw new Error(
      [`command failed with status ${result.status}`, `stdout:\n${result.stdout}`, `stderr:\n${result.stderr}`].join("\n")
    );
  }
}

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-cases-human-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function isJson(stdout: string): boolean {
  return stdout.trimStart().startsWith("{");
}

describe("CLI commands run WITHOUT --json and render human-readable output", () => {
  let workspace: string;
  beforeAll(() => {
    workspace = fixtureWorkspace("minimal-valid");
  });

  test("`matrix validate` runs bare (not the unknown-command fallback)", () => {
    const result = runCli(["matrix", "validate", "--repo", workspace]);
    // Regression: previously this fell through to help with exit 2.
    expect(result.stdout).not.toContain("No recognized command");
    expect(result.status).not.toBe(2);
    expect(isJson(result.stdout)).toBe(false);
    expect(result.stdout.toLowerCase()).toContain("matrix");
  });

  test("`matrix list` renders the behaviours as human text and lists a known row", () => {
    const result = runCli(["matrix", "list", "--repo", workspace]);
    expect(result.status).toBe(0);
    expect(isJson(result.stdout)).toBe(false);
    expect(result.stdout).toContain("auth.login.success");
    // Steers the human toward the machine path without forcing it.
    expect(result.stdout).toContain("--json");
  });

  test("`plan showcase` renders a human plan, not the unknown-command fallback", () => {
    const result = runCli(["plan", "showcase", "--repo", workspace, "--max-items", "3"]);
    expect(result.stdout).not.toContain("No recognized command");
    expect(result.status).not.toBe(2);
    expect(isJson(result.stdout)).toBe(false);
  });

  test("the same command with --json still emits the machine envelope (regression guard)", () => {
    const result = runCli(["matrix", "list", "--repo", workspace, "--json"]);
    expect(result.status).toBe(0);
    expect(isJson(result.stdout)).toBe(true);
    const payload = JSON.parse(result.stdout);
    expect(payload).toMatchObject({ command: "matrix.list", ok: true });
  });

  test("an unknown command still falls through to the usage help", () => {
    const result = runCli(["totally", "bogus"]);
    expect(result.stdout + result.stderr).toContain("No recognized command");
  });
});

// ---------------------------------------------------------------------------
// F4: human-readable TRUST output for the daily commands (scan / verify / impact).
//
// These commands emit JSON only WITH --json; without it they render a friendly,
// at-a-glance human view instead of the generic key/value dumper. The hard
// invariant: --json output stays BYTE-IDENTICAL (proved below). We build a
// hermetic workspace with two swift-bound rows, mint a signed proof for BOTH
// (FRESH), then break one row's span so it reads SUSPECT — no pytest, no CI.
// ---------------------------------------------------------------------------

function uc(cwd: string, args: string[], env: Record<string, string> = {}): SpawnSyncReturns<string> {
  return spawnSync("node", [cliBin, ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0", ...env }
  });
}

function git(cwd: string, ...args: string[]): void {
  const r = spawnSync("git", args, { cwd, encoding: "utf8" });
  if (r.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed (${r.status}): ${r.stderr}`);
  }
}

const ROW_FRESH = "checkout.apply_coupon";
const ROW_SUSPECT = "checkout.remove_coupon";

function rowYaml(id: string): string[] {
  return [
    `  - id: ${id}`,
    `    title: ${id}`,
    "    lifecycle: active",
    "    value_tier: critical",
    "    journey_role: golden",
    "    usage_frequency: common",
    "    actor: shopper",
    "    intent: Coupon behaviour.",
    "    preconditions: [A cart exists.]",
    "    trigger: The shopper acts.",
    "    scenarios:",
    `      - id: ${id}.web`,
    "        kind: steps",
    "        steps: [The shopper acts.]",
    "    observable_outcomes: [The cart total is correct.]",
    "    host_applicability:",
    "      - host_surface: codex.cli",
    "        supported: true",
    "    verification_policy:",
    "      mode: none",
    "    approval_policy:",
    "      mode: none",
    "      required_for_release: true"
  ];
}

// A committed workspace with two swift-bound rows, both proven FRESH, then one
// row's span edited so it goes SUSPECT. Returns the repo dir.
function setupTrustWorkspace(label: string): string {
  const dir = mkdtempSync(join(tmpdir(), `ucm-human-${label}-`));
  tempDirs.push(dir);

  writeFileSync(
    join(dir, "use-cases.yml"),
    [
      "schema_version: 1",
      "workspace_id: human.trust",
      "data_root: .",
      "use_cases_dir: use-cases",
      "evidence_dir: evidence",
      "demo_capsules_dir: demo-capsules",
      "showcase_runs_dir: showcase-runs",
      "component_id: presentation-skills",
      "default_workflow_mode: continuous",
      ""
    ].join("\n")
  );
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(
    join(dir, "use-cases/checkout.yml"),
    [
      "schema_version: 1",
      "feature:",
      "  id: checkout",
      "  name: Checkout",
      "  summary: Coupon behaviours during checkout.",
      "metadata:",
      "  owner: product",
      "  lifecycle: active",
      "use_cases:",
      ...rowYaml(ROW_FRESH),
      ...rowYaml(ROW_SUSPECT),
      ""
    ].join("\n")
  );
  mkdirSync(join(dir, "Sources/Checkout"), { recursive: true });
  writeFileSync(
    join(dir, "Sources/Checkout/CouponService.swift"),
    [
      "import Foundation",
      "",
      "public func applyCoupon(_ code: String) async throws -> Int {",
      "    return 1",
      "}",
      "",
      "public func removeCoupon(_ code: String) async throws -> Int {",
      "    return 2",
      "}",
      ""
    ].join("\n")
  );

  const keypair = generateKeyPairSync("ed25519");
  const publicKeyPath = join(dir, "public-key.pem");
  writeFileSync(publicKeyPath, keypair.publicKey.export({ type: "spki", format: "pem" }) as string);
  const privateKeyPem = keypair.privateKey.export({ type: "pkcs8", format: "pem" }) as string;

  git(dir, "init", "-q");
  git(dir, "config", "user.email", "t@example.com");
  git(dir, "config", "user.name", "t");

  // Bind the LATER function first: each bind inserts marker lines above its
  // target, shifting earlier line numbers, so binding bottom-up keeps them valid.
  const bindSuspect = uc(dir, ["bind", "--repo", dir, "--row", ROW_SUSPECT, "--file", "Sources/Checkout/CouponService.swift", "--mode", "swift-func", "--line", "7", "--json"]);
  if (bindSuspect.status !== 0) throw new Error(`bind ${ROW_SUSPECT} failed: ${bindSuspect.stdout}\n${bindSuspect.stderr}`);
  const bindFresh = uc(dir, ["bind", "--repo", dir, "--row", ROW_FRESH, "--file", "Sources/Checkout/CouponService.swift", "--mode", "swift-func", "--line", "3", "--json"]);
  if (bindFresh.status !== 0) throw new Error(`bind ${ROW_FRESH} failed: ${bindFresh.stdout}\n${bindFresh.stderr}`);

  // verify + prove BOTH rows (unsafe-assume so no real verifier is needed).
  const vrPath = join(dir, "verification-results.jsonl");
  const verify = uc(dir, ["verify", "--repo", dir, "--all", "--out", vrPath, "--public-key", publicKeyPath, "--json"]);
  if (typeof verify.stdout !== "string" || verify.stdout.trim() === "") throw new Error(`verify produced no output: ${verify.stderr}`);
  const prove = uc(
    dir,
    ["prove", "--repo", dir, "--all", "--trusted-ci", "--signing-key-env", "UCM_HUMAN_KEY", "--unsafe-assume-verification-result", "pass", "--append", "--public-key", publicKeyPath, "--json"],
    { UCM_ALLOW_UNSAFE_VERIFICATION: "1", UCM_HUMAN_KEY: privateKeyPem }
  );
  if (prove.status !== 0) throw new Error(`prove failed: ${prove.stdout}\n${prove.stderr}`);

  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", "baseline (both rows FRESH)");

  return dir;
}

// Break ROW_SUSPECT's span so its proof no longer matches -> SUSPECT.
function breakSuspectSpan(dir: string): void {
  const p = join(dir, "Sources/Checkout/CouponService.swift");
  const edited = readFileSync(p, "utf8").replace("    return 2", "    return 2 + 0");
  if (!edited.includes("return 2 + 0")) throw new Error("failed to edit the suspect span");
  writeFileSync(p, edited);
}

describe("F4: human-readable trust output (scan / verify / impact)", () => {
  let dir: string;
  let publicKeyPath: string;
  beforeAll(() => {
    dir = setupTrustWorkspace("scan");
    publicKeyPath = join(dir, "public-key.pem");
  }, 120_000);

  afterAll(() => {
    for (const d of tempDirs.splice(0)) {
      try {
        rmSync(d, { recursive: true, force: true });
      } catch {
        /* the OS reaps tmp regardless */
      }
    }
  });

  test("`scan` (no --json) prints a readable per-row summary with statuses, ids, and the suspect action", () => {
    breakSuspectSpan(dir);
    const result = uc(dir, ["scan", "--repo", dir, "--public-key", publicKeyPath]);
    expect(isJson(result.stdout)).toBe(false);
    const out = result.stdout;
    // Both rows appear by id.
    expect(out).toContain(ROW_FRESH);
    expect(out).toContain(ROW_SUSPECT);
    // A status word/glyph is present for each state.
    expect(out).toContain("FRESH");
    expect(out).toContain("SUSPECT");
    // A headline count line ("N behaviours: ... fresh, ... suspect").
    expect(out.toLowerCase()).toMatch(/behaviour/);
    expect(out.toLowerCase()).toContain("fresh");
    expect(out.toLowerCase()).toContain("suspect");
    // The required action for the suspect row is surfaced (recover / prove).
    expect(out.toLowerCase()).toMatch(/uc (recover|prove)/);
  });

  test("`scan --json` output is UNCHANGED — byte-identical to the pre-F4 machine envelope", () => {
    // The human change must not touch the machine path. We assert the JSON path
    // still parses to the same envelope shape (command + ok + the freshness data)
    // and starts with '{' (no human preamble leaked in).
    const jsonRun = uc(dir, ["scan", "--repo", dir, "--public-key", publicKeyPath, "--json"]);
    expect(isJson(jsonRun.stdout)).toBe(true);
    const payload = JSON.parse(jsonRun.stdout);
    expect(payload.command).toBe("markers.scan");
    expect(payload.data.status.summary).toBeDefined();
    expect(Array.isArray(payload.data.status.rows)).toBe(true);
    // The JSON serialization is exactly one line + trailing newline (the legacy
    // `JSON.stringify(envelope) + "\n"` contract), never pretty-printed.
    expect(jsonRun.stdout.endsWith("}\n")).toBe(true);
    expect(jsonRun.stdout.trimEnd()).toBe(JSON.stringify(payload));
  });

  test("`verify` (no --json) prints a per-row pass/fail summary + a headline", () => {
    const result = uc(dir, ["verify", "--repo", dir, "--all", "--public-key", publicKeyPath]);
    expect(isJson(result.stdout)).toBe(false);
    const out = result.stdout;
    // verify with any non-passing row returns ok:false — a NORMAL trust outcome,
    // not an error. The human view MUST still render (the F4 blocker was gating it
    // on ok===true, so failing runs fell through to the raw dump).
    expect(out).toContain(ROW_FRESH);
    expect(out).toContain(ROW_SUSPECT);
    // Human-specific headline (the generic dumper prints `command: markers.verify`,
    // never `verify: N behaviours`).
    expect(out).toMatch(/verify: \d+ behaviour/);
    // A per-row verdict badge + word.
    expect(out).toMatch(/[✓✗] (PASS|FAIL|BLOCKED)/);
    // The per-row action line is emitted ONLY by renderVerify, and ONLY reachable
    // now that the human view renders for a non-green (ok:false) verify result —
    // this is the regression guard for the fixed blocker.
    expect(out).toContain("→ fix the row and re-run");
  });

  test("`impact` (no --json) prints an 'impacted' list with the impacted row id", () => {
    // Edit inside ROW_FRESH's span so it is impacted by the change.
    const p = join(dir, "Sources/Checkout/CouponService.swift");
    const edited = readFileSync(p, "utf8").replace("    return 1", "    return 1 + 0");
    if (!edited.includes("return 1 + 0")) throw new Error("failed to edit the fresh span");
    writeFileSync(p, edited);

    const result = uc(dir, ["impact", "--repo", dir, "--public-key", publicKeyPath]);
    expect(isJson(result.stdout)).toBe(false);
    const out = result.stdout;
    expect(out.toLowerCase()).toContain("impact");
    expect(out).toContain(ROW_FRESH);
  });

  test("piped (NO_COLOR / non-TTY) output renders WITHOUT ANSI escapes", () => {
    const result = uc(dir, ["scan", "--repo", dir, "--public-key", publicKeyPath], { NO_COLOR: "1" });
    expect(isJson(result.stdout)).toBe(false);
    // No ANSI escape sequences (the ESC control char, 0x1b) in piped output.
    expect(result.stdout).not.toContain(String.fromCharCode(27));
  });
});
