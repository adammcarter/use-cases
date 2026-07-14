// 0.4.1 — the tool must hand you the NEXT COMMAND, not just a verdict.
//
// Two field reports, same complaint: the tool describes state and leaves the
// reader to work out the cure. This pins the two places 0.4.1 fixed that, at the
// CLI level (the surface an agent actually sees):
//
//   1. `uc bind` succeeds and FEELS like progress, so rows get bound and left
//      UNPROVEN forever ("all 7 of my rows are in exactly that state right now").
//      A successful bind must name the command that actually proves the row.
//   2. Integrity errors were JSON-only and cure-free — the human view showed none
//      of them, so a broken registry was invisible unless you reached for --json.
//      They must render, and each must carry a runnable remediation.
import { spawnSync } from "node:child_process";
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const exampleDir = join(repoRoot, "examples/python-pytest");
const cliBin = join(repoRoot, "packages/cli/dist/index.js");
const ROW_ID = "example.checkout.apply_coupon";

const tempDirs: string[] = [];

function uc(cwd: string, ...args: string[]) {
  return spawnSync("node", [cliBin, ...args], {
    cwd,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function workspace(label: string): string {
  const dir = mkdtempSync(join(tmpdir(), `ucm-actionable-${label}-`));
  tempDirs.push(dir);
  cpSync(exampleDir, dir, { recursive: true });
  return dir;
}

function bind(dir: string, ...extra: string[]) {
  return uc(dir, "bind", "--repo", dir, "--row", ROW_ID, "--file", "src/coupon.py",
    "--mode", "explicit", "--register-existing", ...extra);
}

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

describe("bind tells you the row proves nothing yet", () => {
  test("a successful bind names `uc verify --row <id>` as the next command", () => {
    const dir = workspace("bind");
    const result = bind(dir, "--json");

    expect(result.status).toBe(0);
    const payload = JSON.parse(result.stdout) as { data: { next_command?: string } };
    expect(payload.data.next_command).toBe(`uc verify --row ${ROW_ID}`);
  });

  test("the human view surfaces it too", () => {
    const dir = workspace("bind-human");
    const out = bind(dir).stdout;

    expect(out).toContain(`uc verify --row ${ROW_ID}`);
  });
});

describe("integrity errors are visible and carry a cure", () => {
  // Rename the row in the matrix AND in the source marker, leaving the binding
  // registry holding the old id. This is the single most common thing that happens
  // to a codebase between binding a row and verifying it.
  function renameRow(dir: string): void {
    const renamed = "example.checkout.apply_discount_code";
    for (const rel of ["use-cases/checkout.yml", "src/coupon.py"]) {
      const path = join(dir, rel);
      writeFileSync(path, readFileSync(path, "utf8").split(ROW_ID).join(renamed));
    }
  }

  test("a renamed row: scan RENDERS the integrity errors and names the rename", () => {
    const dir = workspace("rename");
    expect(bind(dir, "--json").status).toBe(0);
    renameRow(dir);

    const out = uc(dir, "scan", "--repo", dir).stdout;

    // They render at all — previously the human view showed none of them.
    expect(out).toContain("integrity errors");
    expect(out).toContain("REGISTRY_ROW_MISSING");
    expect(out).toContain("UNREGISTERED_BINDING");

    // Each names the rename rather than only describing the wreckage.
    expect(out).toContain("renamed to example.checkout.apply_discount_code");
    expect(out).toContain(`renamed from ${ROW_ID}`);
  });

  test("the remediation tells the truth: the stale registration must go first", () => {
    const dir = workspace("rename-cure");
    expect(bind(dir, "--json").status).toBe(0);
    renameRow(dir);

    const out = uc(dir, "scan", "--repo", dir).stdout;

    // The registry is append-only with NO retract event, and `uc bind` validates the
    // registry first — so it fails CLOSED on this very error. Advice that omits this
    // sends the reader in a circle.
    expect(out).toContain(".use-cases/bindings.jsonl");
    expect(out).toContain("--register-existing");
  });

  test("and that remediation actually works, end to end", () => {
    const dir = workspace("rename-heal");
    expect(bind(dir, "--json").status).toBe(0);
    renameRow(dir);

    const renamed = "example.checkout.apply_discount_code";
    const registry = join(dir, ".use-cases/bindings.jsonl");

    // Step 1, exactly as the remediation instructs: drop the stale registration.
    const kept = readFileSync(registry, "utf8")
      .split("\n")
      .filter((line) => line.trim() !== "" && !line.includes(ROW_ID));
    writeFileSync(registry, kept.length === 0 ? "" : `${kept.join("\n")}\n`);

    // Step 2: re-register the new id.
    const rebind = uc(dir, "bind", "--repo", dir, "--row", renamed, "--file", "src/coupon.py",
      "--register-existing", "--json");
    expect(rebind.status).toBe(0);

    // The registry is healed: no integrity errors remain.
    const scan = uc(dir, "scan", "--repo", dir, "--json");
    const payload = JSON.parse(scan.stdout) as {
      data: { status: { integrity_errors: unknown[] } };
    };
    expect(payload.data.status.integrity_errors).toHaveLength(0);
  });
});
