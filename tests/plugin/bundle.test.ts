import { execFileSync, spawn, spawnSync } from "node:child_process";
import { once } from "node:events";
import { cpSync, existsSync, mkdtempSync, mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");
const BUNDLE_FILES = ["dist/uc.js", "dist/uc-mcp.js"] as const;

// A "clean clone": every git-tracked (or not-yet-ignored) file, nothing else — no node_modules, no
// packages/*/dist. This is exactly what an agent host has after cloning the repo
// as a plugin.
let cleanClone: string;

function trackedFiles(): string[] {
  return execFileSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], { cwd: repoRoot, encoding: "utf8" })
    .split("\0")
    .filter(Boolean);
}

beforeAll(() => {
  cleanClone = mkdtempSync(join(tmpdir(), "use-cases-clean-clone-"));
  for (const file of trackedFiles()) {
    const target = join(cleanClone, file);
    mkdirSync(dirname(target), { recursive: true });
    cpSync(join(repoRoot, file), target);
  }
});

afterAll(() => {
  if (cleanClone) rmSync(cleanClone, { recursive: true, force: true });
});

function runNode(cwd: string, args: string[]) {
  return spawnSync("node", args, { cwd, encoding: "utf8", env: { ...process.env, NODE_OPTIONS: "" } });
}

//: @use-case:plugin.bundle.runs_from_clean_clone
describe("plugin bundle runs from a clean clone", () => {
  test("the clean clone has no node_modules and no packages/*/dist", () => {
    expect(existsSync(join(cleanClone, "node_modules"))).toBe(false);
    for (const pkg of readdirSync(join(cleanClone, "packages"))) {
      expect(existsSync(join(cleanClone, "packages", pkg, "dist"))).toBe(false);
    }
  });

  test("node dist/uc.js version --json reports the tool from a clean clone", () => {
    const result = runNode(cleanClone, ["dist/uc.js", "version", "--json"]);
    expect(result.status, result.stderr).toBe(0);
    const envelope = JSON.parse(result.stdout);
    expect(envelope.command).toBe("version");
    expect(envelope.data.version).toBe(JSON.parse(readFileSync(join(repoRoot, "package.json"), "utf8")).version);
  });

  test("node dist/uc-mcp.js initializes and lists tools over stdio from a clean clone", async () => {
    const child = spawn("node", ["dist/uc-mcp.js"], { cwd: cleanClone, stdio: ["pipe", "pipe", "pipe"] });
    const exited = once(child, "exit");
    const lines: string[] = [];
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk: string) => lines.push(...chunk.split("\n").map((l) => l.trim()).filter(Boolean)));
    child.stderr.on("data", (chunk: string) => (stderr += chunk));
    const send = (msg: object) => child.stdin.write(`${JSON.stringify(msg)}\n`);
    send({ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2024-11-05", capabilities: {}, clientInfo: { name: "bundle-test", version: "0" } } });
    send({ jsonrpc: "2.0", method: "notifications/initialized" });
    send({ jsonrpc: "2.0", id: 2, method: "tools/list", params: {} });
    const deadline = Date.now() + 15_000;
    while (lines.length < 2 && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
    child.stdin.end();
    await exited;
    expect(lines.length, stderr).toBeGreaterThanOrEqual(2);
    const tools = JSON.parse(lines[1]).result.tools.map((t: { name: string }) => t.name);
    expect(tools).toEqual(expect.arrayContaining(["matrix_validate", "use_case_upsert", "showcase_start"]));
  });

  test("schemas and marker validators resolve from the bundle, not from packages/*/dist", () => {
    const fixture = join(cleanClone, "tests/fixtures/workspaces/minimal-valid");
    const validate = runNode(cleanClone, ["dist/uc.js", "matrix", "validate", "--repo", fixture, "--json"]);
    expect(validate.status, validate.stderr).toBe(0);
    expect(JSON.parse(validate.stdout).ok).toBe(true);
    const scan = runNode(cleanClone, ["dist/uc.js", "scan", "--repo", cleanClone, "--json"]);
    expect(scan.status, scan.stderr).toBe(0);
    expect(JSON.parse(scan.stdout).ok).toBe(true);
  });

  test("the committed bundle matches a fresh build from source", () => {
    const out = mkdtempSync(join(tmpdir(), "use-cases-bundle-rebuild-"));
    try {
      const build = spawnSync("node", ["scripts/bundle.mjs", "--out", out], { cwd: repoRoot, encoding: "utf8" });
      expect(build.status, build.stderr).toBe(0);
      const drifted = BUNDLE_FILES.filter((file) => {
        const committed = readFileSync(join(repoRoot, file));
        const fresh = readFileSync(join(out, file.replace(/^dist\//, "")));
        return !committed.equals(fresh);
      });
      expect(drifted, "committed dist/ is stale — run `pnpm bundle` and commit the result").toEqual([]);
    } finally {
      rmSync(out, { recursive: true, force: true });
    }
  });
});
//: @use-case:end plugin.bundle.runs_from_clean_clone
