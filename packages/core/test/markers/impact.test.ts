// Acceptance tests for the `impact` core command (0.2.0 F2). Each test builds a
// REAL temp git repo, binds a row to an explicit span, commits, then mutates the
// working tree and asserts how impact classifies the binding. These exercise the
// real binding + git-diff code paths end to end (no mocked diff), and pin the
// read-only invariant: running impact must never change a scan verdict or write a
// ledger.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync, existsSync, rmSync, renameSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, describe, expect, test } from "vitest";
import {
  resolveWorkspaceContext,
  runBindCommand,
  runScanCommand,
  runImpactCommand,
  singleKeyResolver
} from "../../src/index.js";
import { generateKeyPairSync } from "node:crypto";

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
    trigger: The shopper submits a coupon code.
    scenarios:
      - id: ${ROW_ID}.web
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

// A source file with a clearly bounded function, so the explicit span brackets a
// small block and we can edit lines inside vs outside it deterministically.
const SOURCE = `import Foundation

func computeTax() -> Int {
    let rate = 1
    let base = 2
    return rate + base
}

func unrelated() -> Int {
    return 0
}
`;

const keypair = generateKeyPairSync("ed25519");
const resolver = singleKeyResolver(keypair.publicKey);

const tempDirs: string[] = [];
afterEach(() => {
  while (tempDirs.length > 0) {
    const dir = tempDirs.pop();
    if (dir) {
      rmSync(dir, { recursive: true, force: true });
    }
  }
});

function git(root: string, ...args: string[]): string {
  return execFileSync("git", args, { cwd: root, encoding: "utf8" });
}

function writeFile(root: string, relPath: string, contents: string): void {
  const full = join(root, relPath);
  mkdirSync(dirname(full), { recursive: true });
  writeFileSync(full, contents);
}

interface Fixture {
  root: string;
  context: ReturnType<typeof resolveWorkspaceContext>;
  bindingsPath: string;
  evidencePath: string;
  boundSpan: { start_line: number; end_line: number };
  boundSlug: string;
}

let idCounter = 0;
function makeId(): () => string {
  return () => `01JIMPACT${String(idCounter++).padStart(17, "0")}`;
}

// Build a real git repo with a bound row, committed, so working-tree diffs work.
function makeFixture(): Fixture {
  const root = mkdtempSync(join(tmpdir(), "impact-"));
  tempDirs.push(root);
  writeFile(root, "use-cases.yml", CONFIG_YAML);
  writeFile(root, "use-cases/checkout.yml", USE_CASE_YAML);
  writeFile(root, "src/tax.swift", SOURCE);

  const context = resolveWorkspaceContext({ workspaceRoot: root });
  const bindingsPath = join(context.data_root, ".use-cases", "bindings.jsonl");
  const evidencePath = join(context.data_root, ".use-cases", "proofs.jsonl");

  // Bind an explicit span around the computeTax() body (lines 3..6 pre-marker).
  const bindResult = runBindCommand({
    context,
    productRoot: context.workspace_root,
    bindingsPath,
    rowId: ROW_ID,
    file: "src/tax.swift",
    mode: "explicit",
    startLine: 3,
    endLine: 6,
    commentPrefix: "//",
    clock: () => GENERATED_AT,
    idFactory: makeId()
  });
  expect(bindResult.exit_code).toBe(0);

  // Read the ACTUAL scanned span (bind inserts marker lines, shifting numbers).
  const scanResult = runScanCommand({
    context,
    productRoot: context.workspace_root,
    bindingsPath,
    evidencePath,
    policyMode: "feature",
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
  const row = scanResult.status.rows.find((candidate) => candidate.row_id === ROW_ID);
  expect(row).toBeDefined();
  expect(row!.current_bindings.length).toBe(1);
  const binding = row!.current_bindings[0];

  git(root, "init", "-q");
  git(root, "config", "user.email", "a@b.c");
  git(root, "config", "user.name", "t");
  git(root, "add", "use-cases.yml", "use-cases/checkout.yml", "src/tax.swift", ".use-cases/bindings.jsonl");
  git(root, "commit", "-qm", "init");

  return {
    root,
    context,
    bindingsPath,
    evidencePath,
    boundSpan: { start_line: binding.span_start_line, end_line: binding.span_end_line },
    boundSlug: binding.binding_slug
  };
}

function scan(fx: Fixture) {
  return runScanCommand({
    context: fx.context,
    productRoot: fx.context.workspace_root,
    bindingsPath: fx.bindingsPath,
    evidencePath: fx.evidencePath,
    policyMode: "feature",
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT
  });
}

function impact(fx: Fixture, opts: { base?: string; staged?: boolean } = {}) {
  return runImpactCommand({
    context: fx.context,
    productRoot: fx.context.workspace_root,
    bindingsPath: fx.bindingsPath,
    evidencePath: fx.evidencePath,
    publicKeyResolver: resolver,
    generatedAt: GENERATED_AT,
    repoCwd: fx.root,
    base: opts.base,
    staged: opts.staged
  });
}

// Replace a single 1-based line's text in a file (keeps line count stable, so it
// is a MODIFY hunk at exactly that line).
function editLine(root: string, relPath: string, lineNo: number, replacement: string): void {
  const full = join(root, relPath);
  const lines = readFileSync(full, "utf8").split("\n");
  lines[lineNo - 1] = replacement;
  writeFileSync(full, lines.join("\n"));
}

describe("impact command", () => {
  test("1: editing a line INSIDE the bound span lists the row as impacted with the overlapping range", () => {
    const fx = makeFixture();
    const inside = fx.boundSpan.start_line + 1; // a body line strictly inside the span
    editLine(fx.root, "src/tax.swift", inside, "    let rate = 999");

    const result = impact(fx);
    expect(result.exit_code).toBe(0);
    expect(result.impacted).toHaveLength(1);
    expect(result.impacted[0].row_id).toBe(ROW_ID);
    expect(result.impacted[0].binding_slug).toBe(fx.boundSlug);
    expect(result.impacted[0].file).toBe("src/tax.swift");
    // The overlapping range covers the edited line.
    const ranges = result.impacted[0].overlapping_ranges;
    expect(ranges.some((r) => r.start_line <= inside && inside <= r.end_line)).toBe(true);
    expect(result.touched).toHaveLength(0);
    expect(result.broken_bindings).toHaveLength(0);
  });

  test("2: editing a line in the bound file OUTSIDE the span lists the row as touched, not impacted", () => {
    const fx = makeFixture();
    // The `unrelated()` body sits well after the span; edit a line there.
    editLine(fx.root, "src/tax.swift", 10, "    return 42");

    const result = impact(fx);
    expect(result.exit_code).toBe(0);
    expect(result.impacted).toHaveLength(0);
    expect(result.touched).toHaveLength(1);
    expect(result.touched[0].row_id).toBe(ROW_ID);
    expect(result.touched[0].binding_slug).toBe(fx.boundSlug);
    expect(result.broken_bindings).toHaveLength(0);
  });

  test("3: editing an UNBOUND file touches no rows", () => {
    const fx = makeFixture();
    writeFile(fx.root, "src/other.swift", "func x() {}\n");
    // Stage-agnostic working-tree change to an untracked file also shows in diff
    // once added; add it so `git diff HEAD` sees it.
    git(fx.root, "add", "src/other.swift");

    const result = impact(fx);
    expect(result.exit_code).toBe(0);
    expect(result.impacted).toHaveLength(0);
    expect(result.touched).toHaveLength(0);
    expect(result.broken_bindings).toHaveLength(0);
    // The unbound file is still reported among changed files (informational).
    expect(result.changed_files.some((f) => f.file === "src/other.swift")).toBe(true);
  });

  test("4: --base <ref> compares against that ref", () => {
    const fx = makeFixture();
    // Commit an inside-span edit on a branch, then compare the branch tip to main.
    const inside = fx.boundSpan.start_line + 1;
    git(fx.root, "branch", "-M", "main");
    git(fx.root, "checkout", "-qb", "feature");
    editLine(fx.root, "src/tax.swift", inside, "    let rate = 7");
    git(fx.root, "commit", "-qam", "tweak inside span");

    // Working tree == feature tip (clean), so default (vs HEAD) sees nothing...
    const clean = impact(fx);
    expect(clean.impacted).toHaveLength(0);
    // ...but comparing against main surfaces the committed in-span edit.
    const vsMain = impact(fx, { base: "main" });
    expect(vsMain.exit_code).toBe(0);
    expect(vsMain.base).toBe("main");
    expect(vsMain.impacted).toHaveLength(1);
    expect(vsMain.impacted[0].row_id).toBe(ROW_ID);
  });

  test("5: deleting the bound file lists the row under broken_bindings", () => {
    const fx = makeFixture();
    git(fx.root, "rm", "-q", "src/tax.swift");

    const result = impact(fx);
    expect(result.exit_code).toBe(0);
    expect(result.impacted).toHaveLength(0);
    expect(result.touched).toHaveLength(0);
    expect(result.broken_bindings).toHaveLength(1);
    expect(result.broken_bindings[0].row_id).toBe(ROW_ID);
    expect(result.broken_bindings[0].binding_slug).toBe(fx.boundSlug);
    expect(result.broken_bindings[0].file).toBe("src/tax.swift");
    expect(result.broken_bindings[0].reason).toBe("deleted");
  });

  test("5b: git-renaming the bound file away lists the row under broken_bindings", () => {
    const fx = makeFixture();
    git(fx.root, "mv", "src/tax.swift", "src/tax_moved.swift");

    const result = impact(fx);
    expect(result.exit_code).toBe(0);
    expect(result.broken_bindings).toHaveLength(1);
    expect(result.broken_bindings[0].row_id).toBe(ROW_ID);
    expect(result.broken_bindings[0].reason).toBe("renamed");
  });

  test("6: no changes at all yields empty impacted/touched and exit 0", () => {
    const fx = makeFixture();
    const result = impact(fx);
    expect(result.exit_code).toBe(0);
    expect(result.impacted).toHaveLength(0);
    expect(result.touched).toHaveLength(0);
    expect(result.broken_bindings).toHaveLength(0);
    expect(result.changed_files).toHaveLength(0);
  });

  test("7: carries a readable human summary line", () => {
    const fx = makeFixture();
    const inside = fx.boundSpan.start_line + 1;
    editLine(fx.root, "src/tax.swift", inside, "    let rate = 999");
    const result = impact(fx);
    expect(typeof result.summary).toBe("string");
    expect(result.summary).toMatch(/impacted/i);
  });

  test("8: impact writes NO ledger and does not change the scan verdict", () => {
    const fx = makeFixture();
    const inside = fx.boundSpan.start_line + 1;
    editLine(fx.root, "src/tax.swift", inside, "    let rate = 999");

    // Snapshot ledger files + the scan status BEFORE impact.
    const bindingsBefore = readFileSync(fx.bindingsPath, "utf8");
    const evidenceExistedBefore = existsSync(fx.evidencePath);
    const statusBefore = JSON.stringify(scan(fx).status);

    const result = impact(fx);
    expect(result.exit_code).toBe(0);

    // Ledgers untouched: bindings byte-identical, proofs still absent.
    expect(readFileSync(fx.bindingsPath, "utf8")).toBe(bindingsBefore);
    expect(existsSync(fx.evidencePath)).toBe(evidenceExistedBefore);
    // No verification-results ledger conjured either.
    expect(existsSync(join(fx.context.data_root, ".use-cases", "verification-results.jsonl"))).toBe(false);
    // The freshness verdict is identical before and after running impact.
    expect(JSON.stringify(scan(fx).status)).toBe(statusBefore);
  });

  test("--staged only reflects the index, not unstaged edits", () => {
    const fx = makeFixture();
    const inside = fx.boundSpan.start_line + 1;
    editLine(fx.root, "src/tax.swift", inside, "    let rate = 5");
    // Unstaged: --staged sees nothing.
    expect(impact(fx, { staged: true }).impacted).toHaveLength(0);
    // Stage it: now --staged surfaces the in-span change.
    git(fx.root, "add", "src/tax.swift");
    const staged = impact(fx, { staged: true });
    expect(staged.impacted).toHaveLength(1);
    expect(staged.impacted[0].row_id).toBe(ROW_ID);
  });
});
