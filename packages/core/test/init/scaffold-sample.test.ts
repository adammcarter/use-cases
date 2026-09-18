import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { afterEach, beforeEach, describe, expect, test } from "vitest";
import { scaffoldWorkspace } from "../../src/init/scaffold.js";

const repoRootOfPlugin = resolve(import.meta.dirname, "../../../..");
const uc = join(repoRootOfPlugin, "dist/uc.js");

function ucJson(args: string[], cwd: string): any {
  const result = spawnSync("node", [uc, ...args, "--json"], { cwd, encoding: "utf8" });
  return JSON.parse(result.stdout);
}

//: @use-case:plugin.init.vends_sample_matrix
describe("use-cases init vends a sample row that shows the whole shape", () => {
  let repoRoot: string;
  beforeEach(() => { repoRoot = mkdtempSync(join(tmpdir(), "ucm-init-sample-")); scaffoldWorkspace({ repoRoot }); });
  afterEach(() => { rmSync(repoRoot, { recursive: true, force: true }); });

  test("the sample row has golden, bad and edge scenarios and a comment on every field", () => {
    const body = readFileSync(join(repoRoot, "use-cases/example.yml"), "utf8");
    for (const kind of ["golden", "bad", "edge"]) {
      expect(body, kind).toMatch(new RegExp(`- id: [a-z_.]+\\.${kind}[a-z_]*\\n`));
    }
    expect(body).toMatch(/one test/i);
    for (const field of ["value_tier", "journey_role", "usage_frequency", "source_refs", "actor", "intent", "preconditions", "trigger", "scenarios", "observable_outcomes", "verification_policy", "approval_policy"]) {
      const line = body.split("\n").findIndex((l) => l.trimStart().startsWith(`${field}:`));
      expect(line, field).toBeGreaterThan(0);
      const above = body.split("\n").slice(Math.max(0, line - 3), line).join("\n");
      expect(above, `comment above ${field}`).toMatch(/#/);
    }
  });

  test("the fresh workspace validates clean", () => {
    const out = ucJson(["matrix", "validate", "--repo", repoRoot], repoRoot);
    expect(out.ok).toBe(true);
    expect(out.data.valid).toBe(true);
  });

  test("the fresh workspace scans with the sample UNBOUND and nothing INVALID", () => {
    const out = ucJson(["scan", "--repo", repoRoot], repoRoot);
    expect(out.ok).toBe(true);
    const rows = out.data.status.rows as Array<{ row_id: string; status: string }>;
    expect(rows.length).toBeGreaterThan(0);
    expect(rows.every((r) => r.status === "UNBOUND")).toBe(true);
    expect(out.data.status.summary.invalid).toBe(0);
  });
});
//: @use-case:end plugin.init.vends_sample_matrix
