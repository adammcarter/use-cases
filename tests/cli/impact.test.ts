// `uc impact` acceptance (0.2.0 F2): the advisory change-impact map.
//
// Given a git change, `uc impact` reports which BOUND behaviours the change
// touches, so you know what to re-verify — via line-level overlap between the
// diff hunks and each binding's span. It is ADVISORY and READ-ONLY: it never
// changes a trust verdict and never writes a ledger.
//
// Runs the BUILT CLI against a real temp git repo (copied from the python-pytest
// example, which ships a marked src/coupon.py + a matrix row), so the whole path
// — git diff, binding materialization, overlap classification — is exercised
// end to end. Hermetic: temp dirs removed in afterAll.
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const exampleDir = join(repoRoot, "examples/python-pytest");
const cliBin = join(repoRoot, "packages/cli/dist/index.js");
const ROW_ID = "example.checkout.apply_coupon";
const IN_SPAN_LINE = "return subtotal_cents - discount"; // a code line inside the bound span

const tempDirs: string[] = [];

function git(cwd: string, ...args: string[]): void {
  const r = spawnSync("git", args, { cwd, encoding: "utf8" });
  if (r.status !== 0) {
    throw new Error(`git ${args.join(" ")} failed (${r.status}): ${r.stderr}`);
  }
}

function uc(cwd: string, ...args: string[]) {
  return spawnSync("node", [cliBin, ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function ucJson(cwd: string, ...args: string[]): { status: number | null; ok: boolean; data: Record<string, any> } {
  const r = uc(cwd, ...args);
  if (typeof r.stdout !== "string" || r.stdout.trim() === "") {
    throw new Error(`uc ${args.join(" ")} produced no JSON (status ${r.status}, stderr: ${r.stderr})`);
  }
  const payload = JSON.parse(r.stdout) as { ok: boolean; data: Record<string, any> };
  return { status: r.status, ok: payload.ok, data: payload.data };
}

function couponPath(dir: string): string {
  return join(dir, "src/coupon.py");
}

// A committed repo with ROW_ID bound to the existing marker in src/coupon.py.
function setupBoundRepo(label: string): string {
  const dir = mkdtempSync(join(tmpdir(), `ucm-impact-${label}-`));
  tempDirs.push(dir);
  cpSync(exampleDir, dir, { recursive: true });
  git(dir, "init", "-q");
  git(dir, "config", "user.email", "t@example.com");
  git(dir, "config", "user.name", "t");

  const bind = uc(dir, "bind", "--repo", dir, "--row", ROW_ID, "--file", "src/coupon.py", "--mode", "explicit", "--register-existing", "--json");
  if (bind.status !== 0) {
    throw new Error(`bind failed (${bind.status}): ${bind.stdout}\n${bind.stderr}`);
  }
  git(dir, "add", "-A");
  git(dir, "commit", "-q", "-m", "baseline");
  return dir;
}

function editInSpan(dir: string): void {
  const p = couponPath(dir);
  const edited = readFileSync(p, "utf8").replace(IN_SPAN_LINE, `${IN_SPAN_LINE} - 0`);
  if (!edited.includes(`${IN_SPAN_LINE} - 0`)) {
    throw new Error("failed to edit the in-span line (source shape changed)");
  }
  writeFileSync(p, edited);
}

describe("uc impact: change-impact map", () => {
  beforeAll(() => {
    const build = spawnSync("corepack", ["pnpm", "build"], {
      cwd: repoRoot,
      encoding: "utf8",
      env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
    });
    if (build.status !== 0) {
      throw new Error(build.stderr || build.stdout);
    }
  }, 180_000);

  afterAll(() => {
    for (const dir of tempDirs.splice(0)) {
      try {
        rmSync(dir, { recursive: true, force: true });
      } catch {
        /* the OS reaps tmp regardless */
      }
    }
  });

  test("edit INSIDE a bound span -> the row is impacted (exit 0)", () => {
    const dir = setupBoundRepo("inspan");
    editInSpan(dir);
    const r = ucJson(dir, "impact", "--repo", dir, "--json");
    expect(r.status).toBe(0);
    expect(r.ok).toBe(true);
    const impactedRows = (r.data.impacted as Array<{ row_id: string }>).map((i) => i.row_id);
    expect(impactedRows).toContain(ROW_ID);
    expect(typeof r.data.summary).toBe("string");
  });

  test("edit an UNBOUND file -> nothing impacted", () => {
    const dir = setupBoundRepo("unbound");
    writeFileSync(join(dir, "NOTES.md"), "just a note\n");
    const r = ucJson(dir, "impact", "--repo", dir, "--json");
    expect(r.status).toBe(0);
    expect((r.data.impacted as unknown[]).length).toBe(0);
    expect((r.data.touched as unknown[]).length).toBe(0);
  });

  // Field report: impact announced "0 behaviours impacted — nothing impacted"
  // directly above a list of rows sitting on files the change had edited. An agent
  // that reads the headline and stops skipped re-verifying exactly the rows that
  // needed it. Span overlap is a weak proxy for behavioural impact — you can gut a
  // function's semantics from a helper below the bound span. The headline must
  // lead with the UNION, and a touched row must carry a runnable next command.
  test("editing a bound file OUTSIDE its span: the headline never claims nothing is impacted", () => {
    const dir = setupBoundRepo("touched");
    // Append a helper BELOW the bound span: same file, span not hit.
    const p = couponPath(dir);
    writeFileSync(p, `${readFileSync(p, "utf8")}\n\ndef unrelated_helper():\n    return 0\n`);

    const r = ucJson(dir, "impact", "--repo", dir, "--json");
    expect(r.status).toBe(0);
    // The span was not hit...
    expect((r.data.impacted as unknown[]).length).toBe(0);
    // ...but the bound file WAS touched.
    const touched = (r.data.touched as Array<{ row_id: string }>).map((t) => t.row_id);
    expect(touched).toContain(ROW_ID);

    // The human headline is the thing that used to lie. It must not say the change
    // impacted nothing while a bound file was touched.
    const human = uc(dir, "impact", "--repo", dir).stdout;
    expect(human).toContain("1 behaviour may be impacted");
    expect(human).toContain("0 span-hit, 1 file-touched");
    expect(human).not.toContain("nothing impacted");
    // And the touched row gets a runnable command, not just a mention.
    expect(human).toContain(`uc verify --row ${ROW_ID}`);
  });

  test("--base compares against a ref", () => {
    const dir = setupBoundRepo("base");
    // Commit an in-span change, then impact vs the PRE-change baseline (HEAD~1).
    editInSpan(dir);
    git(dir, "commit", "-qa", "-m", "in-span change");
    const r = ucJson(dir, "impact", "--repo", dir, "--base", "HEAD~1", "--json");
    expect(r.status).toBe(0);
    const impactedRows = (r.data.impacted as Array<{ row_id: string }>).map((i) => i.row_id);
    expect(impactedRows).toContain(ROW_ID);
  });

  test("ADVISORY + READ-ONLY: impact writes no file and changes no state", () => {
    const dir = setupBoundRepo("readonly");
    editInSpan(dir);
    const status = () => spawnSync("git", ["status", "--porcelain", "-uall"], { cwd: dir, encoding: "utf8" }).stdout;
    const before = status();
    const r = ucJson(dir, "impact", "--repo", dir, "--json");
    expect(r.status).toBe(0);
    // If impact wrote a ledger or any file, git status would differ.
    expect(status()).toBe(before);
  });
});
